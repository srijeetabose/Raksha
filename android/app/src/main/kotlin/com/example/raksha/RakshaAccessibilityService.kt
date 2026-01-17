package com.example.raksha

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class RakshaAccessibilityService : AccessibilityService() {
    
    companion object {
        private const val TAG = "RakshaAccessibilityService"
    }
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "🔓 Raksha Accessibility Service Connected for CROSS-APP detection")
        
        // Start cross-app monitoring
        startCrossAppMonitoring()
        
        Log.d(TAG, "✅ Cross-app accessibility monitoring active")
    }
    
    private fun startCrossAppMonitoring() {
        try {
            Log.d(TAG, "🌐 Starting cross-app monitoring via accessibility service")
            
            // This accessibility service will monitor app changes and trigger gesture detection
            // when the user switches between apps
            
            // Start the foreground service for continuous monitoring
            val intent = Intent(this, RakshaForegroundService::class.java).apply {
                action = RakshaForegroundService.ACTION_START_LISTENER
                putStringArrayListExtra("GESTURES_KEY", ArrayList(listOf("Thumb_Up", "Victory", "Closed_Fist")))
            }
            startForegroundService(intent)
            
            Log.d(TAG, "✅ Cross-app monitoring service started")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting cross-app monitoring: ${e.message}")
        }
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We don't need to process accessibility events for emergency detection
        // This service just ensures we have system-level background access
    }
    
    override fun onInterrupt() {
        Log.d(TAG, "🔓 Raksha Accessibility Service Interrupted")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "🔓 Raksha Accessibility Service Destroyed")
    }
}