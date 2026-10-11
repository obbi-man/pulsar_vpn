//go:build !csclient

package main

import (
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
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
	userWindow     = 5 * time.Minute
	minPad         = 1
	maxPad         = 32
	connIDLen      = 4
	userIDLen      = 16
	timestampLen   = 8
	magicLen       = 4
	nonceLen       = chacha20poly1305.NonceSize
	defaultListen  = ":51820"
	headerPlainLen = magicLen + timestampLen + connIDLen + userIDLen
	dialTimeout    = 12 * time.Second
	idleTimeout    = 120 * time.Second
)

var handshakeMagic = []byte{magic0, magic1, magic2, magic3}

type session struct {
	connID   [connIDLen]byte
	userID   [userIDLen]byte
	lastAddr *net.UDPAddr
	lastSeen time.Time
}

type userRecord struct {
	firstSeen time.Time
	lastSeen  time.Time
}

// tcpTunnel carries one SOCKS CONNECT through the encrypted UDP session.
// Keyed by userID (unique per client SOCKS connection).
type tcpTunnel struct {
	remote    net.Conn
	pc        net.PacketConn
	peer      *net.UDPAddr
	connID    [connIDLen]byte
	userID    [userIDLen]byte
	aead      cipher.AEAD
	closed    chan struct{}
	closeOnce sync.Once
}

// udpFlow is one destination for SOCKS UDP ASSOCIATE / TUN DNS.
type udpFlow struct {
	conn   *net.UDPConn
	target string
}

type udpTunnel struct {
	pc        net.PacketConn
	peer      *net.UDPAddr
	connID    [connIDLen]byte
	userID    [userIDLen]byte
	flows     map[string]*udpFlow
	mu        sync.Mutex
	closed    chan struct{}
	closeOnce sync.Once
}

type server struct {
	aead       cipher.AEAD
	mu         sync.Mutex
	sessions   map[[connIDLen]byte]*session
	users      map[[userIDLen]byte]*userRecord
	tunnels    map[[userIDLen]byte]*tcpTunnel
	udpTunnels map[[userIDLen]byte]*udpTunnel
}

func deriveKey(secret string) []byte {
	sum := sha256.Sum256([]byte(secret))
	return sum[:]
}

func newServer(secret string) (*server, error) {
	aead, err := chacha20poly1305.New(deriveKey(secret))
	if err != nil {
		return nil, err
	}
	return &server{
		aead:       aead,
		sessions:   make(map[[connIDLen]byte]*session),
		users:      make(map[[userIDLen]byte]*userRecord),
		tunnels:    make(map[[userIDLen]byte]*tcpTunnel),
		udpTunnels: make(map[[userIDLen]byte]*udpTunnel),
	}, nil
}

func (s *server) pruneUsers(now time.Time) {
	for id, rec := range s.users {
		if now.Sub(rec.lastSeen) > userWindow {
			delete(s.users, id)
		}
	}
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

func (s *server) seal(plaintext []byte) ([]byte, error) {
	nonce := make([]byte, nonceLen)
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	ciphertext := s.aead.Seal(nil, nonce, plaintext, nil)
	out := make([]byte, 0, nonceLen+len(ciphertext))
	out = append(out, nonce...)
	out = append(out, ciphertext...)
	return addPadding(out)
}

func (s *server) open(packet []byte) ([]byte, error) {
	body, err := stripPadding(packet)
	if err != nil {
		return nil, err
	}
	if len(body) < nonceLen+s.aead.Overhead() {
		return nil, errors.New("ciphertext too short")
	}
	nonce := body[:nonceLen]
	ciphertext := body[nonceLen:]
	return s.aead.Open(nil, nonce, ciphertext, nil)
}

func parseHandshake(plain []byte) (ts int64, connID [connIDLen]byte, userID [userIDLen]byte, payload []byte, err error) {
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

func buildPlaintext(connID [connIDLen]byte, userID [userIDLen]byte, payload []byte) []byte {
	plain := make([]byte, headerPlainLen+len(payload))
	copy(plain[:magicLen], handshakeMagic)
	binary.BigEndian.PutUint64(plain[magicLen:magicLen+timestampLen], uint64(time.Now().Unix()))
	copy(plain[magicLen+timestampLen:], connID[:])
	copy(plain[magicLen+timestampLen+connIDLen:], userID[:])
	copy(plain[headerPlainLen:], payload)
	return plain
}

func (s *server) sendTo(pc net.PacketConn, addr net.Addr, connID [connIDLen]byte, userID [userIDLen]byte, payload []byte) error {
	plain := buildPlaintext(connID, userID, payload)
	packet, err := s.seal(plain)
	if err != nil {
		return err
	}
	_, err = pc.WriteTo(packet, addr)
	return err
}

func (t *tcpTunnel) close() {
	t.closeOnce.Do(func() {
		close(t.closed)
		_ = t.remote.Close()
	})
}

func (s *server) closeTunnel(userID [userIDLen]byte) {
	s.mu.Lock()
	t := s.tunnels[userID]
	delete(s.tunnels, userID)
	s.mu.Unlock()
	if t != nil {
		t.close()
	}
}

func (s *server) pumpRemoteToClient(t *tcpTunnel) {
	defer func() {
		_ = s.sendTo(t.pc, t.peer, t.connID, t.userID, []byte("CLOSE"))
		s.closeTunnel(t.userID)
	}()

	buf := make([]byte, 16*1024)
	for {
		select {
		case <-t.closed:
			return
		default:
		}
		_ = t.remote.SetReadDeadline(time.Now().Add(idleTimeout))
		n, err := t.remote.Read(buf)
		if n > 0 {
			frame := append([]byte("DATA"), buf[:n]...)
			if err := s.sendTo(t.pc, t.peer, t.connID, t.userID, frame); err != nil {
				return
			}
		}
		if err != nil {
			return
		}
	}
}

func (s *server) handleOpen(pc net.PacketConn, addr *net.UDPAddr, connID [connIDLen]byte, userID [userIDLen]byte, target string) {
	target = strings.TrimSpace(target)
	if target == "" {
		_ = s.sendTo(pc, addr, connID, userID, []byte("ERR empty target"))
		return
	}

	// Resolve + dial (DNS happens here on the VPS).
	d := net.Dialer{Timeout: dialTimeout}
	remote, err := d.Dial("tcp", target)
	if err != nil {
		log.Printf("OPEN dial %s failed: %v", target, err)
		_ = s.sendTo(pc, addr, connID, userID, []byte("ERR "+err.Error()))
		return
	}

	s.closeTunnel(userID) // replace any prior tunnel for this stream
	t := &tcpTunnel{
		remote: remote,
		pc:     pc,
		peer:   addr,
		connID: connID,
		userID: userID,
		aead:   s.aead,
		closed: make(chan struct{}),
	}
	s.mu.Lock()
	s.tunnels[userID] = t
	s.mu.Unlock()

	if err := s.sendTo(pc, addr, connID, userID, []byte("OKOPEN")); err != nil {
		s.closeTunnel(userID)
		return
	}
	log.Printf("OPEN %s via conn=%x user=%x", target, connID[:], userID[:4])
	go s.pumpRemoteToClient(t)
}

func (s *server) handleData(userID [userIDLen]byte, data []byte) {
	s.mu.Lock()
	t := s.tunnels[userID]
	s.mu.Unlock()
	if t == nil {
		return
	}
	_ = t.remote.SetWriteDeadline(time.Now().Add(30 * time.Second))
	if _, err := t.remote.Write(data); err != nil {
		s.closeTunnel(userID)
	}
}

func (u *udpTunnel) close() {
	u.closeOnce.Do(func() {
		close(u.closed)
		u.mu.Lock()
		for _, f := range u.flows {
			_ = f.conn.Close()
		}
		u.flows = nil
		u.mu.Unlock()
	})
}

func (s *server) closeUDPTunnel(userID [userIDLen]byte) {
	s.mu.Lock()
	t := s.udpTunnels[userID]
	delete(s.udpTunnels, userID)
	s.mu.Unlock()
	if t != nil {
		t.close()
	}
}

func (s *server) handleOpenUDP(pc net.PacketConn, addr *net.UDPAddr, connID [connIDLen]byte, userID [userIDLen]byte) {
	s.closeUDPTunnel(userID)
	t := &udpTunnel{
		pc:     pc,
		peer:   addr,
		connID: connID,
		userID: userID,
		flows:  make(map[string]*udpFlow),
		closed: make(chan struct{}),
	}
	s.mu.Lock()
	s.udpTunnels[userID] = t
	s.mu.Unlock()
	_ = s.sendTo(pc, addr, connID, userID, []byte("OKOPENUDP"))
}

// UDATA framing: "UDATA" + u16 hostLen + host + u16 port + payload
func (s *server) handleUDATA(userID [userIDLen]byte, frame []byte) {
	if len(frame) < 5+2 {
		return
	}
	body := frame[5:]
	hostLen := int(binary.BigEndian.Uint16(body[:2]))
	if hostLen <= 0 || len(body) < 2+hostLen+2 {
		return
	}
	host := string(body[2 : 2+hostLen])
	port := binary.BigEndian.Uint16(body[2+hostLen : 2+hostLen+2])
	payload := body[2+hostLen+2:]
	target := net.JoinHostPort(host, fmt.Sprintf("%d", port))

	s.mu.Lock()
	t := s.udpTunnels[userID]
	s.mu.Unlock()
	if t == nil {
		return
	}

	t.mu.Lock()
	flow := t.flows[target]
	if flow == nil {
		raddr, err := net.ResolveUDPAddr("udp", target)
		if err != nil {
			t.mu.Unlock()
			return
		}
		c, err := net.DialUDP("udp", nil, raddr)
		if err != nil {
			t.mu.Unlock()
			return
		}
		flow = &udpFlow{conn: c, target: target}
		t.flows[target] = flow
		go s.pumpUDPFlow(t, flow, host, port)
	}
	t.mu.Unlock()

	_ = flow.conn.SetWriteDeadline(time.Now().Add(15 * time.Second))
	_, _ = flow.conn.Write(payload)
}

func (s *server) pumpUDPFlow(t *udpTunnel, flow *udpFlow, host string, port uint16) {
	buf := make([]byte, 64*1024)
	for {
		select {
		case <-t.closed:
			return
		default:
		}
		_ = flow.conn.SetReadDeadline(time.Now().Add(idleTimeout))
		n, err := flow.conn.Read(buf)
		if n > 0 {
			hostBytes := []byte(host)
			out := make([]byte, 5+2+len(hostBytes)+2+n)
			copy(out, "UDATA")
			binary.BigEndian.PutUint16(out[5:7], uint16(len(hostBytes)))
			copy(out[7:7+len(hostBytes)], hostBytes)
			binary.BigEndian.PutUint16(out[7+len(hostBytes):], port)
			copy(out[7+len(hostBytes)+2:], buf[:n])
			if err := s.sendTo(t.pc, t.peer, t.connID, t.userID, out); err != nil {
				return
			}
		}
		if err != nil {
			return
		}
	}
}

func (s *server) handlePacket(pc net.PacketConn, addr net.Addr, packet []byte) {
	plain, err := s.open(packet)
	if err != nil {
		log.Printf("decrypt failed from %s: %v", addr, err)
		return
	}

	ts, connID, userID, payload, err := parseHandshake(plain)
	if err != nil {
		log.Printf("handshake parse failed from %s: %v", addr, err)
		return
	}

	now := time.Now()
	skew := now.Unix() - ts
	if skew < 0 {
		skew = -skew
	}
	if skew > maxSkewSeconds {
		log.Printf("replay/skew rejected from %s: skew=%ds", addr, skew)
		return
	}

	udpAddr, ok := addr.(*net.UDPAddr)
	if !ok {
		return
	}

	s.mu.Lock()
	s.pruneUsers(now)
	if rec, exists := s.users[userID]; exists {
		rec.lastSeen = now
	} else {
		s.users[userID] = &userRecord{firstSeen: now, lastSeen: now}
	}
	active := len(s.users)

	sess, exists := s.sessions[connID]
	if !exists {
		sess = &session{connID: connID, userID: userID}
		s.sessions[connID] = sess
	}
	// Seamless IP change: same Connection ID keeps the session mapping.
	sess.lastAddr = udpAddr
	sess.lastSeen = now
	sess.userID = userID

	// Update peer address on live tunnels (roaming).
	if t := s.tunnels[userID]; t != nil {
		t.peer = udpAddr
	}
	if ut := s.udpTunnels[userID]; ut != nil {
		ut.peer = udpAddr
	}
	s.mu.Unlock()

	// --- Datapath: TCP CONNECT + UDP ASSOCIATE relay (DNS/dial on VPS) ---
	switch {
	case strings.HasPrefix(string(payload), "OPEN "):
		target := strings.TrimPrefix(string(payload), "OPEN ")
		s.handleOpen(pc, udpAddr, connID, userID, target)
		return
	case string(payload) == "OPENUDP" || strings.HasPrefix(string(payload), "OPENUDP"):
		s.handleOpenUDP(pc, udpAddr, connID, userID)
		return
	case strings.HasPrefix(string(payload), "UDATA"):
		s.handleUDATA(userID, payload)
		return
	case strings.HasPrefix(string(payload), "DATA"):
		s.handleData(userID, payload[4:])
		return
	case string(payload) == "CLOSEUDP" || strings.HasPrefix(string(payload), "CLOSEUDP"):
		s.closeUDPTunnel(userID)
		_ = s.sendTo(pc, addr, connID, userID, []byte("OKCLOSEUDP"))
		return
	case string(payload) == "CLOSE" || strings.HasPrefix(string(payload), "CLOSE"):
		s.closeTunnel(userID)
		_ = s.sendTo(pc, addr, connID, userID, []byte("OKCLOSE"))
		return
	case string(payload) == "HELLO" || strings.HasPrefix(string(payload), "HELLO"):
		ack := []byte(fmt.Sprintf("OKHELLO|users=%d", active))
		_ = s.sendTo(pc, addr, connID, userID, ack)
		return
	default:
		// Backward-compatible probe / unknown — ACK
		ack := append([]byte("OK"), payload...)
		ack = append(ack, []byte(fmt.Sprintf("|users=%d", active))...)
		_ = s.sendTo(pc, addr, connID, userID, ack)
	}
}

func main() {
	secret := os.Getenv("CS_SECRET_KEY")
	if secret == "" {
		secret = os.Getenv("SECRET_KEY")
	}
	if secret == "" {
		log.Fatal("CS_SECRET_KEY (or SECRET_KEY) is required")
	}

	listenAddr := os.Getenv("CS_LISTEN")
	if listenAddr == "" {
		listenAddr = defaultListen
	}

	srv, err := newServer(secret)
	if err != nil {
		log.Fatalf("init server: %v", err)
	}

	udpAddr, err := net.ResolveUDPAddr("udp", listenAddr)
	if err != nil {
		log.Fatalf("resolve: %v", err)
	}
	pc, err := net.ListenUDP("udp", udpAddr)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	defer pc.Close()

	log.Printf("CustomShield UDP datapath listening on %s (TCP CONNECT relay + DNS on VPS)", listenAddr)

	buf := make([]byte, 64*1024)
	for {
		n, addr, err := pc.ReadFromUDP(buf)
		if err != nil {
			log.Printf("read: %v", err)
			continue
		}
		packet := make([]byte, n)
		copy(packet, buf[:n])
		go srv.handlePacket(pc, addr, packet)
	}
}
