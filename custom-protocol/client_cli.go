//go:build csclient && cscli

package main

import (
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
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
)

var handshakeMagic = []byte{magic0, magic1, magic2, magic3}

type client struct {
	aead   cipher.AEAD
	connID [connIDLen]byte
	userID [userIDLen]byte
	conn   *net.UDPConn
}

func deriveKey(secret string) []byte {
	sum := sha256.Sum256([]byte(secret))
	return sum[:]
}

func newClient(secret, serverAddr string) (*client, error) {
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
	c := &client{aead: aead, conn: conn}
	if _, err := rand.Read(c.connID[:]); err != nil {
		conn.Close()
		return nil, err
	}
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

func (c *client) handshake(payload []byte) ([]byte, error) {
	packet, err := c.seal(c.buildHandshake(payload))
	if err != nil {
		return nil, err
	}
	if err := c.conn.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
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

func main() {
	secret := os.Getenv("CS_SECRET_KEY")
	if secret == "" {
		secret = os.Getenv("SECRET_KEY")
	}
	if secret == "" {
		log.Fatal("CS_SECRET_KEY (or SECRET_KEY) is required")
	}

	serverAddr := "127.0.0.1:51820"
	if len(os.Args) > 1 {
		serverAddr = os.Args[1]
	}
	if v := os.Getenv("CS_SERVER"); v != "" {
		serverAddr = v
	}

	c, err := newClient(secret, serverAddr)
	if err != nil {
		log.Fatalf("client init: %v", err)
	}
	defer c.conn.Close()

	log.Printf("connID=%s userID=%s -> %s", hex.EncodeToString(c.connID[:]), hex.EncodeToString(c.userID[:]), serverAddr)
	resp, err := c.handshake([]byte("HELLO"))
	if err != nil {
		log.Fatalf("handshake: %v", err)
	}
	fmt.Printf("server response: %s\n", string(resp))
}
