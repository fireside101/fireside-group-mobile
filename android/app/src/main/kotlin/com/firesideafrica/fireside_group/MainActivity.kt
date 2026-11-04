package com.firesideafrica.fireside_group

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var updateChannel: MethodChannel? = null
    private var updateHandler: AppUpdateChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        detachUpdates()
        // The handler owns bounded worker admission; replies and activities stay on main.
        updateHandler = AppUpdateChannelHandler(applicationContext)
        updateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "fireside_group/app_updates").also { it.setMethodCallHandler(updateHandler) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        detachUpdates()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        detachUpdates()
        super.onDestroy()
    }

    private fun detachUpdates() {
        updateChannel?.setMethodCallHandler(null)
        updateHandler?.dispose()
        updateChannel = null
        updateHandler = null
    }
}
