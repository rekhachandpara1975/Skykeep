package com.skykeep.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingUpi: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/upi").setMethodCallHandler { call, result ->
            if (call.method != "pay") return@setMethodCallHandler result.notImplemented()
            val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("bad_uri", "missing uri", null)
            if (pendingUpi != null) return@setMethodCallHandler result.error("busy", "payment already open", null)
            val chooser = Intent.createChooser(Intent(Intent.ACTION_VIEW, Uri.parse(uri)), "Pay with")
            try {
                pendingUpi = result
                @Suppress("DEPRECATION")
                startActivityForResult(chooser, UPI_REQUEST)
            } catch (e: ActivityNotFoundException) {
                // Only here do we decide there is no UPI app (never from queryIntentActivities).
                pendingUpi = null
                result.success(mapOf("no_app" to true))
            }
        }
        PlayChannel.register(this, flutterEngine)
    }

    @Deprecated("startActivityForResult is required by UPI intent apps")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != UPI_REQUEST) return
        val r = pendingUpi ?: return
        pendingUpi = null
        val raw = data?.getStringExtra("response") ?: data?.getStringExtra("Status")?.let { "Status=$it" }
        r.success(mapOf("response" to raw, "cancelled" to (resultCode != Activity.RESULT_OK && raw == null)))
    }

    companion object { private const val UPI_REQUEST = 4711 }
}
