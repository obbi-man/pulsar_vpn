package com.customshield.customshield

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import com.customshield.customshield.vpn.CustomShieldVpnService
import com.customshield.customshield.vpn.VpnStateStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "customshield/vpn"
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepareVpnPermission" -> {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            pendingPermissionResult = result
                            startActivityForResult(intent, REQ_VPN_PERMISSION)
                        } else {
                            result.success(true)
                        }
                    }
                    "enableSystemVpn" -> {
                        val port = call.argument<Int>("localProxyPort") ?: 18080
                        val host = call.argument<String>("proxyHost") ?: "127.0.0.1"
                        val prepare = VpnService.prepare(this)
                        if (prepare != null) {
                            result.error(
                                "VPN_PERMISSION_REQUIRED",
                                "User must grant Android VPN permission",
                                mapOf("permissionRequired" to true),
                            )
                            return@setMethodCallHandler
                        }
                        val svc = Intent(this, CustomShieldVpnService::class.java).apply {
                            action = CustomShieldVpnService.ACTION_START
                            putExtra(CustomShieldVpnService.EXTRA_PROXY_PORT, port)
                            putExtra(CustomShieldVpnService.EXTRA_PROXY_HOST, host)
                        }
                        startForegroundService(svc)
                        result.success(mapOf("ok" to true, "platform" to "android"))
                    }
                    "disableSystemVpn" -> {
                        val svc = Intent(this, CustomShieldVpnService::class.java).apply {
                            action = CustomShieldVpnService.ACTION_STOP
                        }
                        startService(svc)
                        result.success(mapOf("ok" to true))
                    }
                    "isVpnActive" -> result.success(VpnStateStore.active)
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN_PERMISSION) {
            val pending = pendingPermissionResult
            pendingPermissionResult = null
            pending?.success(resultCode == Activity.RESULT_OK)
        }
    }

    companion object {
        private const val REQ_VPN_PERMISSION = 1001
    }
}
