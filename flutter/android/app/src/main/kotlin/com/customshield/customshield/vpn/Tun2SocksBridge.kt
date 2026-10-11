package com.customshield.customshield.vpn

import android.util.Log

/**
 * JNI bridge to hev-socks5-tunnel (or compatible tun2socks).
 * Native symbols are provided by `libcustomshield_tun2socks.so` built from cpp/.
 */
object Tun2SocksBridge {
    private const val TAG = "Tun2SocksBridge"
    private var loaded = false

    init {
        try {
            System.loadLibrary("customshield_tun2socks")
            loaded = true
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Native tun2socks library not loaded", e)
            loaded = false
        }
    }

    fun start(tunFd: Int, socksUri: String, tunAddr: String, tunMask: String): Boolean {
        if (!loaded) return false
        return nativeStart(tunFd, socksUri, tunAddr, tunMask) == 0
    }

    fun stop() {
        if (loaded) nativeStop()
    }

    private external fun nativeStart(
        tunFd: Int,
        socksUri: String,
        tunAddr: String,
        tunMask: String,
    ): Int

    private external fun nativeStop()
}
