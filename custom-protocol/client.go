//go:build csclient && !cscli

package main

/*
#include <stdint.h>
*/
import "C"

import (
	"bufio"
	"context"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/chacha20poly1305"
)

const (
	magic0         = 0xAA
	magic1         = 0xBB
	magic2         = 0xCC
	magic3         = 0xDD
	maxSkewSeconds = 30
	minPad         = 1
	maxPad         = 32
	connIDLen      = 4
	userIDLen      = 16
	timestampLen   = 8
	magicLen       = 4
	nonceLen       = chacha20poly1305.NonceSize
	headerPlainLen = magicLen + timestampLen + connIDLen + userIDLen

	csOK              = 0
	csErrAlreadyRunning = 1
	csErrInvalidArgs  = 2
	csErrListen       = 3
	csErrInternal     = 4
	csErrNotRunning   = 5
)

var handshakeMagic = []byte{magic0, magic1, magic2, magic3}

type client struct {
	aead   cipher.AEAD
	connID [connIDLen]byte
	userID [userIDLen]byte
	conn   *net.UDPConn
}

type runtime struct {
	mu       sync.Mutex
	cancel   context.CancelFunc
	listener net.Listener
	wg       sync.WaitGroup
	running  bool
}

var rt runtime

func deriveKey(secret string) []byte {
	sum := sha256.Sum256([]byte(secret))
	return sum[:]
}

func parseConnectionID(raw string) ([connIDLen]byte, error) {
	var out [connIDLen]byte
	raw = strings.TrimSpace(raw)
	if raw == "" {
		if _, err := rand.Read(out[:]); err != nil {
			return out, err
		}
		return out, nil
	}
	if b, err := hex.DecodeString(raw); err == nil && len(b) >= connIDLen {
		copy(out[:], b[:connIDLen])
		return out, nil
	}
	sum := sha256.Sum256([]byte(raw))
	copy(out[:], sum[:connIDLen])
	return out, nil
}

func newClient(secret, serverAddr string, connID [connIDLen]byte) (*client, error) {
	aead, err := chacha20poly1305.New(deriveKey(secret))
	if err != nil {
		return nil, err
	}
	raddr, err := net.ResolveUDPAddr("udp", serverAddr)
	if err != nil {
		return nil, err
	}
	conn, err := net.DialUDP("udp", nil, raddr)
	if err != nil {
		return nil, err
	}
	c := &client{aead: aead, conn: conn, connID: connID}
	if _, err := rand.Read(c.userID[:]); err != nil {
		conn.Close()
		return nil, err
	}
	return c, nil
}

func stripPadding(packet []byte) ([]byte, error) {
	if len(packet) < 1 {
		return nil, errors.New("empty packet")
	}
	padLen := int(packet[0])
	if padLen < minPad || padLen > maxPad {
		return nil, fmt.Errorf("invalid pad length %d", padLen)
	}
	if len(packet) < 1+padLen {
		return nil, errors.New("packet shorter than declared padding")
	}
	return packet[1+padLen:], nil
}

func addPadding(payload []byte) ([]byte, error) {
	var b [1]byte
	if _, err := rand.Read(b[:]); err != nil {
		return nil, err
	}
	padLen := int(b[0]%byte(maxPad-minPad+1)) + minPad
	out := make([]byte, 1+padLen+len(payload))
	out[0] = byte(padLen)
	if _, err := rand.Read(out[1 : 1+padLen]); err != nil {
		return nil, err
	}
	copy(out[1+padLen:], payload)
	return out, nil
}

func (c *client) seal(plaintext []byte) ([]byte, error) {
	nonce := make([]byte, nonceLen)
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	ciphertext := c.aead.Seal(nil, nonce, plaintext, nil)
	out := make([]byte, 0, nonceLen+len(ciphertext))
	out = append(out, nonce...)
	out = append(out, ciphertext...)
	return addPadding(out)
}

func (c *client) open(packet []byte) ([]byte, error) {
	body, err := stripPadding(packet)
	if err != nil {
		return nil, err
	}
	if len(body) < nonceLen+c.aead.Overhead() {
		return nil, errors.New("ciphertext too short")
	}
	nonce := body[:nonceLen]
	ciphertext := body[nonceLen:]
	return c.aead.Open(nil, nonce, ciphertext, nil)
}

func (c *client) buildHandshake(payload []byte) []byte {
	plain := make([]byte, headerPlainLen+len(payload))
	copy(plain[:magicLen], handshakeMagic)
	binary.BigEndian.PutUint64(plain[magicLen:magicLen+timestampLen], uint64(time.Now().Unix()))
	copy(plain[magicLen+timestampLen:], c.connID[:])
	copy(plain[magicLen+timestampLen+connIDLen:], c.userID[:])
	copy(plain[headerPlainLen:], payload)
	return plain
}

func parseResponse(plain []byte) (ts int64, connID [connIDLen]byte, userID [userIDLen]byte, payload []byte, err error) {
	if len(plain) < headerPlainLen {
		err = errors.New("plaintext too short")
		return
	}
	if plain[0] != magic0 || plain[1] != magic1 || plain[2] != magic2 || plain[3] != magic3 {
		err = errors.New("invalid magic bytes")
		return
	}
	ts = int64(binary.BigEndian.Uint64(plain[magicLen : magicLen+timestampLen]))
	copy(connID[:], plain[magicLen+timestampLen:magicLen+timestampLen+connIDLen])
	copy(userID[:], plain[magicLen+timestampLen+connIDLen:headerPlainLen])
	payload = plain[headerPlainLen:]
	return
}

func (c *client) exchange(payload []byte, deadline time.Duration) ([]byte, error) {
	packet, err := c.seal(c.buildHandshake(payload))
	if err != nil {
		return nil, err
	}
	if err := c.conn.SetDeadline(time.Now().Add(deadline)); err != nil {
		return nil, err
	}
	if _, err := c.conn.Write(packet); err != nil {
		return nil, err
	}

	buf := make([]byte, 64*1024)
	n, err := c.conn.Read(buf)
	if err != nil {
		return nil, err
	}
	_ = c.conn.SetDeadline(time.Time{})

	plain, err := c.open(buf[:n])
	if err != nil {
		return nil, fmt.Errorf("decrypt response: %w", err)
	}
	ts, respConn, _, respPayload, err := parseResponse(plain)
	if err != nil {
		return nil, err
	}
	skew := time.Now().Unix() - ts
	if skew < 0 {
		skew = -skew
	}
	if skew > maxSkewSeconds {
		return nil, fmt.Errorf("response timestamp skew %ds", skew)
	}
	if respConn != c.connID {
		return nil, errors.New("connection id mismatch")
	}
	return respPayload, nil
}

func (c *client) handshake(payload []byte) ([]byte, error) {
	return c.exchange(payload, 5*time.Second)
}

func (c *client) sendFrame(payload []byte) error {
	packet, err := c.seal(c.buildHandshake(payload))
	if err != nil {
		return err
	}
	_, err = c.conn.Write(packet)
	return err
}

func (c *client) readFrame(deadline time.Duration) ([]byte, error) {
	if deadline > 0 {
		if err := c.conn.SetReadDeadline(time.Now().Add(deadline)); err != nil {
			return nil, err
		}
		defer func() { _ = c.conn.SetReadDeadline(time.Time{}) }()
	}
	buf := make([]byte, 64*1024)
	n, err := c.conn.Read(buf)
	if err != nil {
		return nil, err
	}
	plain, err := c.open(buf[:n])
	if err != nil {
		return nil, err
	}
	_, respConn, _, payload, err := parseResponse(plain)
	if err != nil {
		return nil, err
	}
	if respConn != c.connID {
		return nil, errors.New("connection id mismatch")
	}
	// Normalize server control replies used on the data path.
	switch {
	case string(payload) == "OKCLOSE":
		return []byte("CLOSE"), nil
	case strings.HasPrefix(string(payload), "OKHELLO"):
		return payload, nil
	}
	if i := strings.Index(string(payload), "|users="); i >= 0 {
		payload = payload[:i]
	}
	return payload, nil
}

type proxyConfig struct {
	serverAddr string
	secret     string
	connID     [connIDLen]byte
}

func relayThroughCS(ctx context.Context, local net.Conn, cfg proxyConfig, target string) error {
	cs, err := newClient(cfg.secret, cfg.serverAddr, cfg.connID)
	if err != nil {
		return err
	}
	defer cs.conn.Close()

	openPayload := append([]byte("OPEN "), []byte(target)...)
	resp, err := cs.handshake(openPayload)
	if err != nil {
		return fmt.Errorf("cs open: %w", err)
	}
	respStr := string(resp)
	if strings.HasPrefix(respStr, "ERR") {
		return fmt.Errorf("cs open rejected: %s", respStr)
	}
	if !strings.HasPrefix(respStr, "OKOPEN") {
		return fmt.Errorf("cs open unexpected: %q", respStr)
	}

	errCh := make(chan error, 2)

	// local -> CS UDP
	rt.wg.Add(1)
	go func() {
		defer rt.wg.Done()
		buf := make([]byte, 16*1024)
		for {
			_ = local.SetReadDeadline(time.Now().Add(30 * time.Second))
			n, readErr := local.Read(buf)
			if n > 0 {
				frame := append([]byte("DATA"), buf[:n]...)
				if err := cs.sendFrame(frame); err != nil {
					errCh <- err
					return
				}
			}
			if readErr != nil {
				_ = cs.sendFrame([]byte("CLOSE"))
				if errors.Is(readErr, io.EOF) {
					errCh <- nil
				} else {
					errCh <- readErr
				}
				return
			}
			select {
			case <-ctx.Done():
				errCh <- ctx.Err()
				return
			default:
			}
		}
	}()

	// CS UDP -> local
	rt.wg.Add(1)
	go func() {
		defer rt.wg.Done()
		for {
			select {
			case <-ctx.Done():
				errCh <- ctx.Err()
				return
			default:
			}
			payload, err := cs.readFrame(30 * time.Second)
			if err != nil {
				errCh <- err
				return
			}
			if len(payload) == 0 {
				continue
			}
			if string(payload) == "CLOSE" || strings.HasPrefix(string(payload), "CLOSE") {
				errCh <- nil
				return
			}
			data := payload
			if strings.HasPrefix(string(payload), "DATA") {
				data = payload[4:]
			}
			if len(data) == 0 {
				continue
			}
			if _, err := local.Write(data); err != nil {
				errCh <- err
				return
			}
		}
	}()

	err = <-errCh
	_ = local.Close()
	return err
}

func handleSocks5(ctx context.Context, conn net.Conn, br *bufio.Reader, cfg proxyConfig) {
	defer conn.Close()

	header := make([]byte, 2)
	if _, err := io.ReadFull(br, header); err != nil {
		return
	}
	if header[0] != 0x05 {
		return
	}
	nMethods := int(header[1])
	methods := make([]byte, nMethods)
	if _, err := io.ReadFull(br, methods); err != nil {
		return
	}
	// No auth.
	if _, err := conn.Write([]byte{0x05, 0x00}); err != nil {
		return
	}

	req := make([]byte, 4)
	if _, err := io.ReadFull(br, req); err != nil {
		return
	}
	if req[0] != 0x05 {
		return
	}
	// UDP ASSOCIATE
	if req[1] == 0x03 {
		// Drain address + port from request, then bind local UDP relay.
		switch req[3] {
		case 0x01:
			_, _ = io.CopyN(io.Discard, br, 4+2)
		case 0x03:
			lb := make([]byte, 1)
			if _, err := io.ReadFull(br, lb); err != nil {
				return
			}
			_, _ = io.CopyN(io.Discard, br, int64(lb[0])+2)
		case 0x04:
			_, _ = io.CopyN(io.Discard, br, 16+2)
		default:
			_, _ = conn.Write([]byte{0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
			return
		}
		handleSocks5UDPAssociate(ctx, conn, cfg)
		return
	}
	if req[1] != 0x01 {
		_, _ = conn.Write([]byte{0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}

	var host string
	switch req[3] {
	case 0x01: // IPv4
		addr := make([]byte, 4)
		if _, err := io.ReadFull(br, addr); err != nil {
			return
		}
		host = net.IP(addr).String()
	case 0x03: // domain
		lenBuf := make([]byte, 1)
		if _, err := io.ReadFull(br, lenBuf); err != nil {
			return
		}
		domain := make([]byte, int(lenBuf[0]))
		if _, err := io.ReadFull(br, domain); err != nil {
			return
		}
		host = string(domain)
	case 0x04: // IPv6
		addr := make([]byte, 16)
		if _, err := io.ReadFull(br, addr); err != nil {
			return
		}
		host = net.IP(addr).String()
	default:
		_, _ = conn.Write([]byte{0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}
	portBuf := make([]byte, 2)
	if _, err := io.ReadFull(br, portBuf); err != nil {
		return
	}
	port := binary.BigEndian.Uint16(portBuf)
	target := net.JoinHostPort(host, strconv.Itoa(int(port)))

	// Success reply (bind 0.0.0.0:0)
	if _, err := conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil {
		return
	}

	_ = relayThroughCS(ctx, &bufConn{Reader: br, Conn: conn}, cfg, target)
}

func buildUDATA(host string, port int, payload []byte) []byte {
	hb := []byte(host)
	out := make([]byte, 5+2+len(hb)+2+len(payload))
	copy(out, "UDATA")
	binary.BigEndian.PutUint16(out[5:7], uint16(len(hb)))
	copy(out[7:7+len(hb)], hb)
	binary.BigEndian.PutUint16(out[7+len(hb):], uint16(port))
	copy(out[7+len(hb)+2:], payload)
	return out
}

func parseUDATA(frame []byte) (host string, port int, payload []byte, ok bool) {
	if !strings.HasPrefix(string(frame), "UDATA") || len(frame) < 5+2 {
		return "", 0, nil, false
	}
	body := frame[5:]
	hostLen := int(binary.BigEndian.Uint16(body[:2]))
	if hostLen <= 0 || len(body) < 2+hostLen+2 {
		return "", 0, nil, false
	}
	host = string(body[2 : 2+hostLen])
	port = int(binary.BigEndian.Uint16(body[2+hostLen : 2+hostLen+2]))
	payload = body[2+hostLen+2:]
	return host, port, payload, true
}

func handleSocks5UDPAssociate(ctx context.Context, conn net.Conn, cfg proxyConfig) {
	// Reply: success, bind 127.0.0.1:relayPort
	udpAddr, err := net.ResolveUDPAddr("udp", "127.0.0.1:0")
	if err != nil {
		_, _ = conn.Write([]byte{0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}
	pc, err := net.ListenUDP("udp", udpAddr)
	if err != nil {
		_, _ = conn.Write([]byte{0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}
	defer pc.Close()

	bound := pc.LocalAddr().(*net.UDPAddr)
	rep := []byte{0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0}
	binary.BigEndian.PutUint16(rep[8:], uint16(bound.Port))
	if _, err := conn.Write(rep); err != nil {
		return
	}

	cs, err := newClient(cfg.secret, cfg.serverAddr, cfg.connID)
	if err != nil {
		return
	}
	defer cs.conn.Close()

	resp, err := cs.handshake([]byte("OPENUDP"))
	if err != nil || !strings.HasPrefix(string(resp), "OKOPENUDP") {
		return
	}

	errCh := make(chan struct{}, 3)
	var clientMu sync.Mutex
	var clientAddr *net.UDPAddr

	// Keep TCP control connection; close tears down associate.
	go func() {
		buf := make([]byte, 1)
		for {
			if _, err := conn.Read(buf); err != nil {
				errCh <- struct{}{}
				return
			}
			select {
			case <-ctx.Done():
				errCh <- struct{}{}
				return
			default:
			}
		}
	}()

	go func() {
		buf := make([]byte, 64*1024)
		for {
			select {
			case <-ctx.Done():
				errCh <- struct{}{}
				return
			default:
			}
			_ = pc.SetReadDeadline(time.Now().Add(30 * time.Second))
			n, addr, err := pc.ReadFromUDP(buf)
			if err != nil {
				continue
			}
			clientMu.Lock()
			clientAddr = addr
			clientMu.Unlock()
			if n < 10 {
				continue
			}
			// SOCKS5 UDP: RSV RSV FRAG ATYP ...
			atyp := buf[3]
			var host string
			var port int
			var dataOff int
			switch atyp {
			case 0x01:
				host = net.IP(buf[4:8]).String()
				port = int(binary.BigEndian.Uint16(buf[8:10]))
				dataOff = 10
			case 0x03:
				l := int(buf[4])
				if n < 5+l+2 {
					continue
				}
				host = string(buf[5 : 5+l])
				port = int(binary.BigEndian.Uint16(buf[5+l : 5+l+2]))
				dataOff = 5 + l + 2
			default:
				continue
			}
			frame := buildUDATA(host, port, buf[dataOff:n])
			if err := cs.sendFrame(frame); err != nil {
				errCh <- struct{}{}
				return
			}
		}
	}()

	go func() {
		for {
			select {
			case <-ctx.Done():
				errCh <- struct{}{}
				return
			default:
			}
			payload, err := cs.readFrame(30 * time.Second)
			if err != nil {
				errCh <- struct{}{}
				return
			}
			host, port, data, ok := parseUDATA(payload)
			if !ok {
				if string(payload) == "CLOSE" || strings.HasPrefix(string(payload), "CLOSE") {
					errCh <- struct{}{}
					return
				}
				continue
			}
			ip := net.ParseIP(host)
			var hdr []byte
			if ip4 := ip.To4(); ip4 != nil {
				hdr = make([]byte, 10+len(data))
				hdr[3] = 0x01
				copy(hdr[4:8], ip4)
				binary.BigEndian.PutUint16(hdr[8:10], uint16(port))
				copy(hdr[10:], data)
			} else {
				hb := []byte(host)
				hdr = make([]byte, 5+len(hb)+2+len(data))
				hdr[3] = 0x03
				hdr[4] = byte(len(hb))
				copy(hdr[5:], hb)
				binary.BigEndian.PutUint16(hdr[5+len(hb):], uint16(port))
				copy(hdr[5+len(hb)+2:], data)
			}
			clientMu.Lock()
			dst := clientAddr
			clientMu.Unlock()
			if dst != nil {
				_, _ = pc.WriteToUDP(hdr, dst)
			}
		}
	}()

	<-errCh
	_ = cs.sendFrame([]byte("CLOSEUDP"))
	_ = conn.Close()
}

func handleHTTPConnect(ctx context.Context, conn net.Conn, br *bufio.Reader, cfg proxyConfig) {
	defer conn.Close()

	line, err := br.ReadString('\n')
	if err != nil {
		return
	}
	line = strings.TrimRight(line, "\r\n")
	parts := strings.Split(line, " ")
	if len(parts) < 2 || !strings.EqualFold(parts[0], "CONNECT") {
		_, _ = io.WriteString(conn, "HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n")
		return
	}
	target := parts[1]
	// Drain headers.
	for {
		h, err := br.ReadString('\n')
		if err != nil {
			return
		}
		if h == "\r\n" || h == "\n" {
			break
		}
	}
	if _, err := io.WriteString(conn, "HTTP/1.1 200 Connection Established\r\n\r\n"); err != nil {
		return
	}
	_ = relayThroughCS(ctx, &bufConn{Reader: br, Conn: conn}, cfg, target)
}

type bufConn struct {
	*bufio.Reader
	net.Conn
}

func (c *bufConn) Read(p []byte) (int, error) {
	return c.Reader.Read(p)
}

func serveProxy(ctx context.Context, ln net.Listener, cfg proxyConfig) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				// Listener closed or transient accept error.
				if !rt.running {
					return
				}
				time.Sleep(50 * time.Millisecond)
				continue
			}
		}
		rt.wg.Add(1)
		go func(c net.Conn) {
			defer rt.wg.Done()
			br := bufio.NewReader(c)
			peek, err := br.Peek(1)
			if err != nil {
				_ = c.Close()
				return
			}
			if peek[0] == 0x05 {
				handleSocks5(ctx, c, br, cfg)
				return
			}
			handleHTTPConnect(ctx, c, br, cfg)
		}(conn)
	}
}

// StartClient starts a local SOCKS5/HTTP CONNECT proxy that tunnels via CustomShield UDP.
//
//export StartClient
func StartClient(serverIP *C.char, port C.int, secretKey *C.char, connectionID *C.char, localProxyPort C.int) C.int {
	if serverIP == nil || secretKey == nil || port <= 0 || port > 65535 || localProxyPort <= 0 || localProxyPort > 65535 {
		return csErrInvalidArgs
	}

	ip := C.GoString(serverIP)
	secret := C.GoString(secretKey)
	connIDRaw := ""
	if connectionID != nil {
		connIDRaw = C.GoString(connectionID)
	}
	if ip == "" || secret == "" {
		return csErrInvalidArgs
	}

	connID, err := parseConnectionID(connIDRaw)
	if err != nil {
		return csErrInternal
	}

	rt.mu.Lock()
	defer rt.mu.Unlock()
	if rt.running {
		return csErrAlreadyRunning
	}

	addr := net.JoinHostPort("127.0.0.1", strconv.Itoa(int(localProxyPort)))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Printf("StartClient listen failed: %v", err)
		return csErrListen
	}

	ctx, cancel := context.WithCancel(context.Background())
	cfg := proxyConfig{
		serverAddr: net.JoinHostPort(ip, strconv.Itoa(int(port))),
		secret:     secret,
		connID:     connID,
	}

	// Probe CS server once so Flutter gets a fast failure if unreachable.
	probe, err := newClient(secret, cfg.serverAddr, connID)
	if err != nil {
		cancel()
		_ = ln.Close()
		log.Printf("StartClient dial failed: %v", err)
		return csErrInternal
	}
	if _, err := probe.handshake([]byte("HELLO")); err != nil {
		probe.conn.Close()
		cancel()
		_ = ln.Close()
		log.Printf("StartClient handshake failed: %v", err)
		return csErrInternal
	}
	probe.conn.Close()

	rt.cancel = cancel
	rt.listener = ln
	rt.running = true

	rt.wg.Add(1)
	go func() {
		defer rt.wg.Done()
		serveProxy(ctx, ln, cfg)
	}()

	log.Printf("CustomShield local proxy on %s -> %s (connID=%s)", addr, cfg.serverAddr, hex.EncodeToString(connID[:]))
	return csOK
}

// StopClient stops the local proxy and tears down active tunnels.
//
//export StopClient
func StopClient() C.int {
	rt.mu.Lock()
	if !rt.running {
		rt.mu.Unlock()
		return csErrNotRunning
	}
	cancel := rt.cancel
	ln := rt.listener
	rt.running = false
	rt.cancel = nil
	rt.listener = nil
	rt.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	if ln != nil {
		_ = ln.Close()
	}
	done := make(chan struct{})
	go func() {
		rt.wg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		log.Printf("StopClient: timed out waiting for workers")
	}
	log.Printf("CustomShield client stopped")
	return csOK
}

// main is the c-shared / c-archive entrypoint (no-op).
func main() {}
