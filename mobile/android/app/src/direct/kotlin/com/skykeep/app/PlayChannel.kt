package com.skykeep.app

import io.flutter.embedding.engine.FlutterEngine

/** Direct (website/ads) build: no Play libraries, nothing to register. */
object PlayChannel {
    fun register(activity: MainActivity, engine: FlutterEngine) = Unit
}
