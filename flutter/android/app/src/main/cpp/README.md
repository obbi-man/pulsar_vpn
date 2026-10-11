# Android tun2socks (hev-socks5-tunnel)

`CustomShieldVpnService` opens a TUN and calls JNI `Tun2SocksBridge`, which forwards
all IP packets to the Go local SOCKS5 proxy (`127.0.0.1:localProxyPort`).

## Vendor hev-socks5-tunnel

```bash
# from repo root
./flutter/tool/fetch_tun2socks.sh
```

This clones [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) into
`third_party/hev-socks5-tunnel` and enables `HAVE_HEV_SOCKS5_TUNNEL` in CMake.

Without it, the JNI builds in `CS_TUN2SOCKS_STUB` mode (VPN permission + TUN still
work for UX testing; packets are not forwarded).

## Also place Go FFI libs

Copy outputs from `custom-protocol/build-libs.sh` into:

```
android/app/src/main/jniLibs/arm64-v8a/libcustomshield.so
android/app/src/main/jniLibs/armeabi-v7a/libcustomshield.so
android/app/src/main/jniLibs/x86_64/libcustomshield.so
```
