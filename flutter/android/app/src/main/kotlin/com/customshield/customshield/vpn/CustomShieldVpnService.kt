package com.customshield.customshield.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.customshield.customshield.MainActivity
import com.customshield.customshield.R
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android system VPN: creates a TUN iface and forwards all IP traffic to the
 * local SOCKS5 proxy raised by the Go `StartClient` (127.0.0.1:localProxyPort)
 * via hev-socks5-tunnel (JNI).
 */
class CustomShieldVpnService : VpnService() {

    private var tun: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTunnel()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                val port = intent?.getIntExtra(EXTRA_PROXY_PORT, DEFAULT_PORT)
                    ?: DEFAULT_PORT
                val host = intent?.getStringExtra(EXTRA_PROXY_HOST) ?: "127.0.0.1"
                startTunnel(host, port)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    private fun startTunnel(proxyHost: String, proxyPort: Int) {
        if (!running.compareAndSet(false, true)) {
            Log.i(TAG, "VPN already running")
            return
        }

        startForeground(NOTIFICATION_ID, buildNotification("Connecting…"))

        try {
            val builder = Builder()
                .setSession("CustomShield")
                .setMtu(8500)
                .addAddress(TUN_ADDR, 32)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
                .setBlocking(true)

            // Keep local proxy + VPN server path off the TUN.
            builder.allowFamily(android.system.OsConstants.AF_INET)
            try {
                builder.addDisallowedApplication(packageName)
            } catch (_: Exception) {
                // Older APIs may not support disallow; Go proxy uses protect() via JNI if needed.
            }

            val pfd = builder.establish()
            if (pfd == null) {
                throw IllegalStateException("VpnService.Builder.establish() returned null")
            }
            tun = pfd

            val socksUri = "socks5://$proxyHost:$proxyPort"
            val ok = Tun2SocksBridge.start(pfd.fd, socksUri, TUN_ADDR, "255.255.255.255")
            if (!ok) {
                throw IllegalStateException(
                    "tun2socks failed to start. Ensure libhev-socks5-tunnel / JNI libs are built " +
                        "(see android/app/src/main/cpp/README.md).",
                )
            }

            startForeground(NOTIFICATION_ID, buildNotification("Protected · proxy $proxyHost:$proxyPort"))
            VpnStateStore.setActive(true)
            Log.i(TAG, "VPN up → $socksUri")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start VPN", t)
            running.set(false)
            closeTun()
            VpnStateStore.setActive(false)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun stopTunnel() {
        if (!running.getAndSet(false) && tun == null) return
        try {
            Tun2SocksBridge.stop()
        } catch (t: Throwable) {
            Log.w(TAG, "tun2socks stop", t)
        }
        closeTun()
        VpnStateStore.setActive(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        Log.i(TAG, "VPN stopped")
    }

    private fun closeTun() {
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
    }

    private fun buildNotification(content: String): Notification {
        val channelId = "customshield_vpn"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "CustomShield VPN",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("CustomShield")
            .setContentText(content)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(launch)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_START = "com.customshield.customshield.vpn.START"
        const val ACTION_STOP = "com.customshield.customshield.vpn.STOP"
        const val EXTRA_PROXY_PORT = "proxyPort"
        const val EXTRA_PROXY_HOST = "proxyHost"
        private const val DEFAULT_PORT = 18080
        private const val TUN_ADDR = "10.8.0.2"
        private const val NOTIFICATION_ID = 42
        private const val TAG = "CustomShieldVpn"
    }
}

object VpnStateStore {
    @Volatile
    var active: Boolean = false
        private set

    fun setActive(value: Boolean) {
        active = value
    }
}
