package com.happybangladesh.happy_bangladesh

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Battery level (0-100) for the live-map pin; -1 when unknown.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hb/battery").setMethodCallHandler { call, result ->
            if (call.method == "level") {
                val i: Intent? = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val level = i?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = i?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                result.success(if (level >= 0 && scale > 0) level * 100 / scale else -1)
            } else {
                result.notImplemented()
            }
        }
    }
}
