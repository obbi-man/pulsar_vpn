#!/usr/bin/env bash
set -euo pipefail

OPT_DIR="/opt/customshield"
IMAGE_NAME="customshield-proto"
CONTAINER_NAME="customshield-proto"
LISTEN_PORT="${CS_LISTEN_PORT:-51820}"
SECRET_KEY="${CS_SECRET_KEY:-}"

if [[ -z "${SECRET_KEY}" && -f "${OPT_DIR}/.secret" ]]; then
  SECRET_KEY="$(cat "${OPT_DIR}/.secret")"
fi

if [[ -z "${SECRET_KEY}" ]]; then
  SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi

echo "[CustomShield] Ensuring Docker is installed..."
if ! command -v docker >/dev/null 2>&1; then
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
  else
    echo "curl is required to install Docker" >&2
    exit 1
  fi
fi

# Fallback mirror hint used by some environments
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://docker.com | sh || true
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker installation failed" >&2
  exit 1
fi

mkdir -p "${OPT_DIR}"
chmod 755 "${OPT_DIR}"

if [[ -f ./server.go ]]; then
  cp ./server.go "${OPT_DIR}/server.go"
elif [[ -f /tmp/customshield-upload/server.go ]]; then
  cp /tmp/customshield-upload/server.go "${OPT_DIR}/server.go"
else
  echo "server.go not found in current directory or /tmp/customshield-upload" >&2
  exit 1
fi

printf '%s' "${SECRET_KEY}" > "${OPT_DIR}/.secret"
chmod 600 "${OPT_DIR}/.secret"

cat > "${OPT_DIR}/go.mod" <<'EOF'
module customshield

go 1.22

require golang.org/x/crypto v0.31.0

require golang.org/x/sys v0.28.0 // indirect
EOF

cat > "${OPT_DIR}/Dockerfile" <<'EOF'
FROM golang:alpine AS build
WORKDIR /src
COPY go.mod ./
COPY server.go ./
RUN go mod tidy && CGO_ENABLED=0 go build -o /out/customshield-server server.go

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=build /out/customshield-server /app/customshield-server
ENV CS_LISTEN=:51820
EXPOSE 51820/udp
ENTRYPOINT ["/app/customshield-server"]
EOF

# Userspace TCP/UDP CONNECT relay: the container dials the public internet itself.
# Docker MASQUERADE provides outbound NAT — no host iptables/TUN required.
# DNS for OPEN targets is resolved inside the container (needs working resolv.conf).
if [[ -f /proc/sys/net/ipv4/ip_forward ]]; then
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
fi

echo "[CustomShield] Building and starting container..."
cd "${OPT_DIR}"
docker build -t "${IMAGE_NAME}" .
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  --dns 1.1.1.1 \
  --dns 8.8.8.8 \
  -e "CS_SECRET_KEY=${SECRET_KEY}" \
  -e "SECRET_KEY=${SECRET_KEY}" \
  -e "CS_LISTEN=:${LISTEN_PORT}" \
  -p "${LISTEN_PORT}:${LISTEN_PORT}/udp" \
  "${IMAGE_NAME}"

echo "SUCCESS_DEPLOYS"
echo "[CustomShield] Datapath: client SOCKS CONNECT/UDP -> encrypted UDP -> VPS dial/DNS -> internet"
