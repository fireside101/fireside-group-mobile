package com.firesideafrica.fireside_group

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var updateChannel: MethodChannel? = null
    private var updateHandler: AppUpdateChannelHandler? = null
    private var documentChannel: MethodChannel? = null
    private var documentHandler: DocumentDownloadHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        detachUpdates()
        // The handler owns bounded worker admission; replies and activities stay on main.
        updateHandler = AppUpdateChannelHandler(applicationContext)
        updateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "fireside_group/app_updates").also { it.setMethodCallHandler(updateHandler) }
        documentHandler = DocumentDownloadHandler(this)
        documentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "fireside_group/documents").also { it.setMethodCallHandler(documentHandler) }
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
        documentChannel?.setMethodCallHandler(null)
        documentHandler?.dispose()
        documentChannel = null
        documentHandler = null
        updateChannel?.setMethodCallHandler(null)
        updateHandler?.dispose()
        updateChannel = null
        updateHandler = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documentHandler?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
