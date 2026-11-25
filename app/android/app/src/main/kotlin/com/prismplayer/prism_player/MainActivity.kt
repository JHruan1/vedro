package com.prismplayer.prism_player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PrismHardwarePlugin.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
