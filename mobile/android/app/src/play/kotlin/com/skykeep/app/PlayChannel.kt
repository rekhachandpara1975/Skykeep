package com.skykeep.app

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Play Store build only: Play Integrity token for the free 15 GB tier (verified server-side by play-verify).
 * There is no billing here — the Play build never sells anything; UPI checkout exists only in the website / ads APKs.
 */
object PlayChannel {
    fun register(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/play").setMethodCallHandler { call, result ->
            when (call.method) {
                "integrityToken" -> {
                    val nonce = call.argument<String>("nonce") ?: return@setMethodCallHandler result.error("nonce", "missing", null)
                    IntegrityManagerFactory.create(activity.applicationContext)
                        .requestIntegrityToken(IntegrityTokenRequest.builder().setNonce(nonce).build())
                        .addOnSuccessListener { result.success(it.token()) }
                        .addOnFailureListener { result.error("integrity", it.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }
}
