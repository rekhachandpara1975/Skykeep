package com.skykeep.app

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.concurrent.thread

/** 'app/thumb': a JPEG poster frame (and the duration) of a local video, for upload thumbnails. */
object ThumbChannel {
    fun register(engine: FlutterEngine) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/thumb").setMethodCallHandler { call, result ->
            if (call.method != "frame") return@setMethodCallHandler result.notImplemented()
            val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("bad_path", "missing path", null)
            val maxWidth = call.argument<Int>("maxWidth") ?: 640
            thread(name = "thumb") {
                val r = MediaMetadataRetriever()
                try {
                    r.setDataSource(path)
                    val ms = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    // a frame about 10% in (min 1 s) avoids black intro frames; short clips use their middle
                    val at = if (ms <= 2000) ms * 500 else minOf(ms / 10, 10_000L).coerceAtLeast(1000L) * 1000
                    var bmp = r.getFrameAtTime(at, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        ?: r.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    if (bmp == null) {
                        main.post { result.success(null) }
                    } else {
                        if (bmp.width > maxWidth) {
                            val scaled = Bitmap.createScaledBitmap(bmp, maxWidth, (bmp.height * maxWidth.toFloat() / bmp.width).toInt().coerceAtLeast(1), true)
                            if (scaled !== bmp) bmp.recycle()
                            bmp = scaled
                        }
                        val out = ByteArrayOutputStream()
                        bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
                        val bytes = out.toByteArray()
                        main.post { result.success(mapOf("jpeg" to bytes, "durationMs" to ms)) }
                    }
                } catch (e: Exception) {
                    main.post { result.success(null) } // unreadable file: the app just has no auto thumbnail
                } finally {
                    try { r.release() } catch (_: Exception) {}
                }
            }
        }
    }
}
