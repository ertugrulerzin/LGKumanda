package com.ertugrul.lg_kumanda

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.os.Build

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private val permission = "android.permission.ACCESS_LOCAL_NETWORK"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lgkumanda/network")
            .setMethodCallHandler { call, result ->
                if (call.method != "requestLocalNetwork") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < 37 || checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else if (permissionResult != null) {
                    result.error("pending", "İzin isteği zaten açık.", null)
                } else {
                    permissionResult = result
                    requestPermissions(arrayOf(permission), 7430)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7430) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }
}
