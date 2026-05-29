package com.example.raksha

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager

/**
 * Minimal invisible activity — keeps the app process alive.
 * All voice detection is handled by RakshaForegroundService.
 * This activity just prevents Android from killing the process.
 */
class VoiceListenerActivity : Activity() {

    private val TAG = "VoiceListenerActivity"

    private val stopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.raksha.STOP_VOICE_LISTENER") {
                Log.d(TAG, "🛑 Stop received")
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "✅ VoiceListenerActivity created (process anchor)")

        // Invisible 1x1 window
        window.setLayout(1, 1)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopReceiver, IntentFilter("com.example.raksha.STOP_VOICE_LISTENER"), RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(stopReceiver, IntentFilter("com.example.raksha.STOP_VOICE_LISTENER"))
        }

        moveTaskToBack(true)
    }

    override fun onResume() {
        super.onResume()
        moveTaskToBack(true)
    }

    override fun onBackPressed() {
        moveTaskToBack(true)
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(stopReceiver) } catch (e: Exception) { }
        Log.d(TAG, "VoiceListenerActivity destroyed")
    }
}
