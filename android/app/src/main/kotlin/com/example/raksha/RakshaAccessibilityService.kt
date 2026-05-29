package com.example.raksha

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class RakshaAccessibilityService : AccessibilityService(), RecognitionListener {
    
    companion object {
        private const val TAG = "RakshaAccessibilityService"
    }
    
    private var speechRecognizer: SpeechRecognizer? = null
    private var voiceTriggers = mutableListOf<String>()
    private var isListening = false
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "🔓 Raksha Accessibility Service Connected")
        // Voice detection is handled by RakshaForegroundService only
        // Accessibility service is kept for system-wide gesture monitoring only
        Log.d(TAG, "✅ Accessibility service active (voice handled by ForegroundService)")
    }
    
    private fun loadTriggerWords() {
        // Use default triggers - don't access Firebase from accessibility service
        setDefaultTriggers()
    }
    
    private fun setDefaultTriggers() {
        voiceTriggers.clear()
        voiceTriggers.addAll(listOf(
            "help", "danger", "emergency", "police", "rescue",
            "attack", "fire", "thief", "intruder", "accident"
        ))
        Log.d(TAG, "Using default triggers: ${voiceTriggers.size} words")
    }
    
    private fun startVoiceDetection() {
        try {
            Log.d(TAG, "🎤 Starting ACCESSIBILITY voice detection (bypasses Android 15)")
            
            if (SpeechRecognizer.isRecognitionAvailable(this)) {
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer?.setRecognitionListener(this)
                
                // Wait for triggers to load
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    startListening()
                }, 2000)
                
                Log.d(TAG, "✅ Voice detection initialized via accessibility service")
            } else {
                Log.e(TAG, "❌ Speech recognition not available")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting voice detection: ${e.message}")
        }
    }
    
    private fun startListening() {
        if (isListening) return
        
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            }
            
            isListening = true
            speechRecognizer?.startListening(intent)
            Log.d(TAG, "🎤 Listening via accessibility service...")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting listening: ${e.message}")
            isListening = false
        }
    }
    
    // RecognitionListener implementation
    override fun onReadyForSpeech(params: Bundle?) {
        Log.d(TAG, "🎤 Ready for speech")
    }
    
    override fun onBeginningOfSpeech() {
        Log.d(TAG, "🎤 Speech started")
    }
    
    override fun onRmsChanged(rmsdB: Float) {}
    
    override fun onBufferReceived(buffer: ByteArray?) {}
    
    override fun onEndOfSpeech() {
        Log.d(TAG, "🎤 Speech ended")
    }
    
    override fun onError(error: Int) {
        val errorMsg = when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Audio error"
            SpeechRecognizer.ERROR_CLIENT -> "Client error"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "No permission"
            SpeechRecognizer.ERROR_NETWORK -> "Network error"
            SpeechRecognizer.ERROR_NO_MATCH -> "No match"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Busy"
            SpeechRecognizer.ERROR_SERVER -> "Server error"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Timeout"
            13 -> "Android 15 restriction (BYPASSED via accessibility)"
            else -> "Error $error"
        }
        
        Log.e(TAG, "🎤 Error: $errorMsg")
        isListening = false
        
        // Restart after error
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            startListening()
        }, 2000)
    }
    
    override fun onResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            for (match in matches) {
                val spokenText = match.lowercase()
                Log.d(TAG, "🎤 Heard: '$spokenText'")
                
                // Check for triggers
                for (trigger in voiceTriggers) {
                    if (spokenText.contains(trigger)) {
                        Log.d(TAG, "🚨 TRIGGER DETECTED: '$trigger'")
                        launchSOSCountdown(trigger)
                        return
                    }
                }
            }
        }
        
        // Restart listening
        isListening = false
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            startListening()
        }, 500)
    }
    
    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            val spokenText = matches[0].lowercase()
            Log.d(TAG, "🎤 Partial: '$spokenText'")
            
            // Quick check on partial results
            for (trigger in voiceTriggers) {
                if (spokenText.contains(trigger)) {
                    Log.d(TAG, "🚨 TRIGGER DETECTED (partial): '$trigger'")
                    launchSOSCountdown(trigger)
                    return
                }
            }
        }
    }
    
    override fun onEvent(eventType: Int, params: Bundle?) {}
    
    private fun launchSOSCountdown(trigger: String) {
        try {
            Log.d(TAG, "🚀 Launching SOS countdown for: $trigger")
            
            val intent = Intent(this, SOSCountdownActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_NO_HISTORY
                putExtra("TRIGGER_WORD", "Voice: $trigger")
            }
            startActivity(intent)
            
            Log.d(TAG, "✅ SOS countdown launched")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error launching SOS: ${e.message}")
        }
    }
    
    private fun startCrossAppMonitoring() {
        try {
            Log.d(TAG, "🌐 Starting cross-app monitoring via accessibility service")
            
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
        speechRecognizer?.destroy()
    }
}