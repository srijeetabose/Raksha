package com.example.raksha

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.os.Vibrator
import android.os.VibrationEffect
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.NotificationCompat

class RakshaForegroundService : Service(), RecognitionListener {
    
    private var wakeLock: PowerManager.WakeLock? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var voiceTriggers = mutableListOf<String>()
    private var isListeningForVoice = false

    companion object {
        private const val TAG = "RakshaForegroundService"
        const val CHANNEL_ID = "RAKSHA_SOS_CHANNEL"
        const val NOTIFICATION_ID = 101
        const val ACTION_START_LISTENER = "START_LISTENER"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        
        // Acquire wake lock to keep service active
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Raksha::EmergencySystem24x7"
        )
        wakeLock?.acquire(24*60*60*1000L)
        
        Log.d(TAG, "RakshaForegroundService created")
        
        // Start as foreground service immediately
        startForeground(NOTIFICATION_ID, createPersistentNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_LISTENER -> startDetection()
            "EMERGENCY_TRIGGERED" -> {
                val trigger = intent.getStringExtra("trigger") ?: "Unknown"
                Log.d(TAG, "Emergency received: $trigger")
                triggerEmergency(trigger)
            }
        }
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun startDetection() {
        Log.d(TAG, "Starting detection service")
        startForeground(NOTIFICATION_ID, buildNotification())
        
        // Start voice detection
        startVoiceDetection()
        
        Log.d(TAG, "Detection service active")
    }
    
    // Load user's custom trigger words from Firebase
    private fun loadUserTriggerWords() {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .get()
                    .addOnSuccessListener { document ->
                        if (document.exists()) {
                            val triggers = document.get("voiceTriggers") as? List<*>
                            if (triggers != null) {
                                voiceTriggers.clear()
                                for (trigger in triggers) {
                                    if (trigger is String) {
                                        voiceTriggers.add(trigger)
                                    }
                                }
                                Log.d(TAG, "Loaded user's trigger words: $voiceTriggers")
                            } else {
                                setDefaultTriggers()
                            }
                        } else {
                            setDefaultTriggers()
                        }
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "Failed to load trigger words: ${e.message}")
                        setDefaultTriggers()
                    }
            } else {
                setDefaultTriggers()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading trigger words: ${e.message}")
            setDefaultTriggers()
        }
    }
    
    private fun setDefaultTriggers() {
        voiceTriggers.clear()
        voiceTriggers.add("help me")
        voiceTriggers.add("emergency")
        voiceTriggers.add("call police")
        Log.d(TAG, "Using default trigger words: $voiceTriggers")
    }

    private fun startVoiceDetection() {
        try {
            Log.d(TAG, "Starting voice detection...")
            
            // Load user's custom trigger words first
            loadUserTriggerWords()
            
            if (SpeechRecognizer.isRecognitionAvailable(this)) {
                // Destroy any existing recognizer
                speechRecognizer?.destroy()
                
                // Create new recognizer
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer?.setRecognitionListener(this)
                
                // Start listening immediately
                startContinuousListening()
                
                Log.d(TAG, "Voice detection started")
            } else {
                Log.e(TAG, "Speech recognition not available")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting voice detection: ${e.message}")
        }
    }
    
    private fun startContinuousListening() {
        if (isListeningForVoice) {
            Log.d(TAG, "Already listening for voice")
            return
        }
        
        try {
            Log.d(TAG, "Starting continuous voice listening...")
            
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            
            isListeningForVoice = true
            speechRecognizer?.startListening(intent)
            Log.d(TAG, "Voice listening started")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting continuous listening: ${e.message}")
            isListeningForVoice = false
        }
    }
    
    // RecognitionListener implementation
    override fun onReadyForSpeech(params: Bundle?) {
        Log.d(TAG, "Voice ready")
    }
    
    override fun onBeginningOfSpeech() {
        Log.d(TAG, "Speech started")
    }
    
    override fun onRmsChanged(rmsdB: Float) {
        // Sound level monitoring
    }
    
    override fun onBufferReceived(buffer: ByteArray?) {
        // Audio buffer received
    }
    
    override fun onEndOfSpeech() {
        Log.d(TAG, "Speech ended")
    }
    
    override fun onError(error: Int) {
        Log.e(TAG, "Speech error: $error")
        isListeningForVoice = false
        // Restart listening after error
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            startContinuousListening()
        }, 2000)
    }
    
    override fun onResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            for (match in matches) {
                val spokenText = match.lowercase()
                Log.d(TAG, "Heard: '$spokenText'")
                
                // Check user's custom triggers
                for (trigger in voiceTriggers) {
                    if (spokenText.contains(trigger.lowercase())) {
                        Log.d(TAG, "Voice emergency detected: '$trigger'")
                        triggerVoiceEmergency(trigger, spokenText)
                        return
                    }
                }
                
                // Check common emergency words
                val emergencyWords = arrayOf("help", "emergency", "police", "danger", "rescue", "sos")
                for (word in emergencyWords) {
                    if (spokenText.contains(word)) {
                        Log.d(TAG, "Emergency word detected: '$word'")
                        triggerVoiceEmergency(word, spokenText)
                        return
                    }
                }
            }
        }
        
        // Restart listening for continuous detection
        isListeningForVoice = false
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            startContinuousListening()
        }, 500)
    }
    
    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            val spokenText = matches[0].lowercase()
            Log.d(TAG, "Partial: '$spokenText'")
            
            // Quick partial matching for faster detection
            if (spokenText.contains("help") || 
                spokenText.contains("emergency") ||
                spokenText.contains("police")) {
                
                Log.d(TAG, "Voice emergency detected (partial): '$spokenText'")
                triggerVoiceEmergency("emergency", spokenText)
            }
        }
    }
    
    override fun onEvent(eventType: Int, params: Bundle?) {
        // Speech events
    }
    
    private fun triggerVoiceEmergency(trigger: String, fullText: String) {
        try {
            Log.d(TAG, "Triggering voice emergency: '$trigger' from '$fullText'")
            
            // Send broadcast to MainActivity
            val intent = Intent("com.example.raksha.EMERGENCY_GESTURE").apply {
                putExtra("gesture", "VOICE: $trigger")
                putExtra("source", "voice")
                putExtra("type", "voice_trigger")
                putExtra("fullText", fullText)
                putExtra("timestamp", System.currentTimeMillis())
            }
            sendBroadcast(intent)
            
            // Vibrate to alert user
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 200, 500), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(longArrayOf(0, 500, 200, 500), -1)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error triggering voice emergency: ${e.message}")
        }
    }

    private fun triggerEmergency(gestureName: String) {
        Log.d(TAG, "Emergency triggered by: $gestureName")
        
        // Send emergency SMS
        sendEmergencySMS(gestureName)
        
        // Start emergency vibration
        startEmergencyVibration()
        
        // Show confirmation notification
        showEmergencyNotification(gestureName)
        
        // Broadcast emergency to MainActivity
        val emergencyIntent = Intent("com.example.raksha.EMERGENCY_GESTURE")
        emergencyIntent.putExtra("gesture", gestureName)
        emergencyIntent.putExtra("source", "ForegroundService")
        sendBroadcast(emergencyIntent)
    }
    
    private fun sendEmergencySMS(gestureName: String) {
        try {
            Log.d(TAG, "Sending emergency SMS...")
            
            val emergencyMessage = "🚨 EMERGENCY ALERT! Gesture detected: $gestureName. I need help immediately! This is an automated message from Raksha Safety App."
            
            // TODO: Get real emergency contacts from Firebase
            val emergencyContacts = arrayOf("+1234567890", "+0987654321")
            
            @Suppress("DEPRECATION")
            val smsManager = SmsManager.getDefault()
            for (phoneNumber in emergencyContacts) {
                try {
                    smsManager.sendTextMessage(phoneNumber, null, emergencyMessage, null, null)
                    Log.d(TAG, "Emergency SMS sent to: $phoneNumber")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to send SMS to $phoneNumber: ${e.message}")
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error sending emergency SMS: ${e.message}")
        }
    }
    
    private fun showEmergencyNotification(gestureName: String) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚨 EMERGENCY ACTIVATED!")
            .setContentText("Gesture: $gestureName - Emergency SMS sent")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(false)
            .setOngoing(true)
            .build()
            
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(999, notification)
    }
    
    private fun startEmergencyVibration() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 1000, 500, 1000, 500), 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(longArrayOf(0, 1000, 500, 1000, 500), 0)
            }
            Log.d(TAG, "Emergency vibration started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start vibration: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Raksha Gesture Detection",
                NotificationManager.IMPORTANCE_LOW
            )
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🛡️ Raksha Active")
            .setContentText("Voice detection active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        
        // Clean up speech recognizer
        speechRecognizer?.destroy()
        
        // Release wake lock
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        
        Log.d(TAG, "RakshaForegroundService destroyed")
    }
    
    // Create persistent notification to keep service active
    private fun createPersistentNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🛡️ Raksha Protection Active")
            .setContentText("🎤 Voice detection across ALL apps - Say 'help me' for emergency")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
}