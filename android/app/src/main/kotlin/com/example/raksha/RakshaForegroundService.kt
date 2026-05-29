package com.example.raksha

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.os.Vibrator
import android.os.VibrationEffect
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlin.math.sqrt

class RakshaForegroundService : Service(), RecognitionListener, SensorEventListener {

    private var wakeLock: PowerManager.WakeLock? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var voiceTriggers = mutableListOf<String>()
    private var isListeningForVoice = false
    private var voiceLanguage = "en-IN"
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())


    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var lastShakeTime = 0L
    private var shakeCount = 0
    private val SHAKE_THRESHOLD = 25f      // Very hard shake only (normal movement ~5, running ~12)
    private val SHAKE_COUNT_REQUIRED = 5   // Must shake 5 times
    private val SHAKE_RESET_MS = 1500L     // Within 1.5 seconds

    // Cooldown
    private var lastTriggerTime = 0L
    private val TRIGGER_COOLDOWN_MS = 30 * 1000L

    companion object {
        private const val TAG = "RakshaForegroundService"
        const val CHANNEL_ID = "RAKSHA_SOS_CHANNEL"
        const val NOTIFICATION_ID = 101
        const val ACTION_START_LISTENER = "START_LISTENER"
        const val EXTRA_TRIGGERS = "VOICE_TRIGGERS"
    }

    private val safeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            Log.d(TAG, "✅ I AM SAFE — resetting cooldown")
            lastTriggerTime = 0L
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "Raksha::EmergencySystem24x7"
        )
        wakeLock?.acquire(24 * 60 * 60 * 1000L)

        val filter = IntentFilter("com.example.raksha.I_AM_SAFE")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(safeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(safeReceiver, filter)
        }

        startForeground(NOTIFICATION_ID, createPersistentNotification(),
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)

        // Shake detection works 24/7 in background — no camera needed
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        accelerometer?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
            Log.d(TAG, "✅ Shake detection started")
        }

        Log.d(TAG, "✅ RakshaForegroundService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: action=${intent?.action}")

        val passedTriggers = intent?.getStringArrayListExtra(EXTRA_TRIGGERS)
        if (!passedTriggers.isNullOrEmpty()) {
            voiceTriggers.clear()
            passedTriggers.forEach { voiceTriggers.add(it.lowercase()) }
            Log.d(TAG, "✅ Got ${voiceTriggers.size} triggers: $voiceTriggers")
            isListeningForVoice = false
            speechRecognizer?.destroy()
            speechRecognizer = null
            startVoiceDetection()
        } else {
            // Always reload from Firebase — never use stale cached triggers
            isListeningForVoice = false
            speechRecognizer?.destroy()
            speechRecognizer = null
            loadTriggersFromFirebaseThenStart()
        }

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val restartIntent = Intent(applicationContext, RakshaForegroundService::class.java).apply {
            action = ACTION_START_LISTENER
            putStringArrayListExtra(EXTRA_TRIGGERS, ArrayList(voiceTriggers))
        }
        val pendingIntent = PendingIntent.getService(
            this, 1, restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        alarmManager.set(
            android.app.AlarmManager.ELAPSED_REALTIME,
            android.os.SystemClock.elapsedRealtime() + 1000,
            pendingIntent
        )
        Log.d(TAG, "App removed — scheduled restart")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Firebase trigger loading ──────────────────────────────────────────────

    private fun loadTriggersFromFirebaseThenStart() {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users").document(userId).get()
                    .addOnSuccessListener { doc ->
                        val raw = doc.get("triggerVoiceWords") as? List<*>
                            ?: doc.get("voiceTriggers") as? List<*>
                        if (raw != null) {
                            voiceTriggers.clear()
                            raw.filterIsInstance<String>().forEach { voiceTriggers.add(it.lowercase()) }
                            Log.d(TAG, "✅ Firebase triggers: $voiceTriggers")
                        } else {
                            setDefaultTriggers()
                        }
                        // Load language preference
                        voiceLanguage = doc.getString("voiceLanguage") ?: "en-IN"
                        Log.d(TAG, "✅ Voice language: $voiceLanguage")
                        startVoiceDetection()
                    }
                    .addOnFailureListener {
                        setDefaultTriggers()
                        startVoiceDetection()
                    }
            } else {
                setDefaultTriggers()
                startVoiceDetection()
            }
        } catch (e: Exception) {
            setDefaultTriggers()
            startVoiceDetection()
        }
    }

    private fun setDefaultTriggers() {
        // Do NOT set any default triggers — if the user hasn't configured trigger words,
        // voice detection should stay silent. We never want to trigger SOS on generic speech.
        voiceTriggers.clear()
        Log.d(TAG, "⚠️ No trigger words configured by user — voice SOS disabled until user sets them up")
    }

    // ── Voice detection ───────────────────────────────────────────────────────

    private fun startVoiceDetection() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "❌ RECORD_AUDIO not granted — retrying in 30s")
                handler.postDelayed({ startVoiceDetection() }, 30000)
                return
            }
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.e(TAG, "❌ Speech recognition not available")
            return
        }
        Log.d(TAG, "🎤 Starting SpeechRecognizer with: $voiceTriggers")
        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(this)
        handler.postDelayed({ startContinuousListening() }, 500)
    }

    private fun startContinuousListening() {
        if (isListeningForVoice) return
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                // Use device language — supports all Indian languages
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, voiceLanguage)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, voiceLanguage)
                // Also accept other languages
                putExtra("android.speech.extra.EXTRA_ADDITIONAL_LANGUAGES", arrayOf(
                    "hi-IN", "bn-IN", "ta-IN", "te-IN", "kn-IN",
                    "ml-IN", "mr-IN", "gu-IN", "pa-IN", "or-IN", "ur-IN", "en-IN"
                ))
                putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, false)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            }
            isListeningForVoice = true
            speechRecognizer?.startListening(intent)
            Log.d(TAG, "🎤 Listening... triggers=$voiceTriggers")
        } catch (e: Exception) {
            Log.e(TAG, "Error: ${e.message}")
            isListeningForVoice = false
            handler.postDelayed({ startContinuousListening() }, 3000)
        }
    }

    // ── RecognitionListener ───────────────────────────────────────────────────

    override fun onReadyForSpeech(params: Bundle?) { Log.d(TAG, "🎤 Ready") }
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onEvent(eventType: Int, params: Bundle?) {}

    override fun onError(error: Int) {
        isListeningForVoice = false
        val delay = when (error) {
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> 3000L
            SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> 300L
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> 30000L
            else -> 2000L
        }
        Log.d(TAG, "Speech error: $error — retrying in ${delay}ms")
        handler.postDelayed({ startContinuousListening() }, delay)
    }

    override fun onResults(results: Bundle?) {
        isListeningForVoice = false
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
            for (match in matches) {
                val spoken = match.trim()
                Log.d(TAG, "🎤 Heard: '$spoken'")
                // Run NLP distress detection pipeline
                analyzeForDistress(spoken)
            }
        }
        handler.postDelayed({ startContinuousListening() }, 300)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
            val spoken = matches[0].trim()
            // Quick check on partial results too
            analyzeForDistress(spoken)
        }
    }

    // ── NLP Distress Detection Pipeline ──────────────────────────────────────

    private val distressKeywords = setOf(
        // English distress phrases
        "help", "danger", "emergency", "police", "rescue", "attack",
        "fire", "thief", "accident", "hurt", "pain", "scared", "afraid",
        "threat", "weapon", "knife", "gun", "bleeding", "unconscious",
        "following me", "chasing", "kidnap", "assault", "rape", "murder",
        "save me", "call police", "need help", "please help", "someone help",
        "let me go", "don't hurt", "stop it", "leave me", "get away"
    )

    private fun analyzeForDistress(spokenText: String) {
        if (spokenText.length < 2) return

        // If the user hasn't configured any trigger words, do nothing.
        if (voiceTriggers.isEmpty()) {
            Log.d(TAG, "⚠️ No trigger words configured — ignoring speech")
            return
        }

        val spokenLower = spokenText.lowercase().trim()

        // Rule: utterance must contain "raksha" (or common phonetic variants)
        // AND one of the user's 3 chosen trigger words.
        // This prevents any single word from accidentally firing SOS.
        val rakshaVariants = listOf(
            "raksha", "raksa", "raksha", "रक्षा", "রক্ষা", "ரக்ஷா",
            "రక్ష", "ರಕ್ಷ", "രക്ഷ", "रक्षा", "રક્ષા", "ਰੱਖਿਆ",
            "ରକ୍ଷା", "رکشا"
        )
        val hasRaksha = rakshaVariants.any { spokenLower.contains(it) }

        if (!hasRaksha) {
            Log.d(TAG, "✅ No 'Raksha' prefix — ignoring: '$spokenLower'")
            return
        }

        // "Raksha" detected — now check if any of the user's trigger words follow
        for (trigger in voiceTriggers) {
            if (spokenLower.contains(trigger.lowercase())) {
                Log.d(TAG, "🚨 TRIGGER MATCH: 'Raksha' + '$trigger' in '$spokenLower'")
                triggerEmergency("Voice: $trigger", spokenText)
                handler.postDelayed({ startContinuousListening() }, 20000)
                return
            }
        }

        Log.d(TAG, "✅ 'Raksha' heard but no trigger word matched in: '$spokenLower'")
    }

    private fun translateToEnglish(text: String, sourceLang: String) {
        // Use MyMemory free translation API (no key needed, 1000 req/day)
        val encodedText = java.net.URLEncoder.encode(text, "UTF-8")
        val url = "https://api.mymemory.translated.net/get?q=$encodedText&langpair=$sourceLang|en"

        Thread {
            try {
                val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                connection.connectTimeout = 3000
                connection.readTimeout = 3000
                val response = connection.inputStream.bufferedReader().readText()
                val json = org.json.JSONObject(response)
                val translated = json.getJSONObject("responseData")
                    .getString("translatedText")
                Log.d(TAG, "🌐 Translated: '$text' → '$translated'")
                handler.post { checkEnglishForDistress(translated) }
            } catch (e: Exception) {
                Log.e(TAG, "Translation failed: ${e.message}")
                // Fallback: check original text
                handler.post { checkEnglishForDistress(text) }
            }
        }.start()
    }

    private fun checkEnglishForDistress(text: String) {
        val lower = text.lowercase()
        for (keyword in distressKeywords) {
            if (lower.contains(keyword)) {
                Log.d(TAG, "🚨 NLP DISTRESS DETECTED: '$keyword' in '$lower'")
                triggerEmergency("Distress: $keyword", text)
                handler.postDelayed({ startContinuousListening() }, 20000)
                return
            }
        }
        Log.d(TAG, "✅ No distress detected in: '$lower'")
    }

    // ── Shake detection ───────────────────────────────────────────────────────

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_ACCELEROMETER) return
        val x = event.values[0]; val y = event.values[1]; val z = event.values[2]
        val accel = sqrt((x * x + y * y + z * z).toDouble()).toFloat() - SensorManager.GRAVITY_EARTH
        if (accel > SHAKE_THRESHOLD) {
            val now = System.currentTimeMillis()
            if (now - lastShakeTime > SHAKE_RESET_MS) shakeCount = 0
            shakeCount++
            lastShakeTime = now
            if (shakeCount >= SHAKE_COUNT_REQUIRED) {
                shakeCount = 0
                Log.d(TAG, "🚨 SHAKE TRIGGER!")
                triggerEmergency("Shake", "device shaken")
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // ── Emergency trigger ─────────────────────────────────────────────────────

    private fun triggerEmergency(trigger: String, fullText: String) {
        val now = System.currentTimeMillis()
        if (now - lastTriggerTime < TRIGGER_COOLDOWN_MS) {
            Log.d(TAG, "⏳ Cooldown — ignoring '$trigger'")
            return
        }
        lastTriggerTime = now

        try {
            handler.post {
                android.widget.Toast.makeText(this, "🚨 $trigger", android.widget.Toast.LENGTH_LONG).show()
            }

            // Start SOSNotificationService — shows 10s countdown notification with CANCEL button
            val sosIntent = Intent(this, SOSNotificationService::class.java).apply {
                putExtra("TRIGGER_WORD", trigger)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(sosIntent)
            } else {
                startService(sosIntent)
            }

            sendBroadcast(Intent("com.example.raksha.EMERGENCY_GESTURE").apply {
                putExtra("gesture", trigger)
                putExtra("source", "background_service")
                putExtra("fullText", fullText)
                putExtra("timestamp", now)
            })

            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager).defaultVibrator
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
            Log.e(TAG, "Error triggering: ${e.message}")
        }
    }

    // ── Notifications ─────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Raksha Protection", NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun createPersistentNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🛡️ Raksha Active")
            .setContentText("Voice & shake detection running")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        sensorManager?.unregisterListener(this)
        try { unregisterReceiver(safeReceiver) } catch (e: Exception) { }
        speechRecognizer?.destroy()
        handler.removeCallbacksAndMessages(null)
        wakeLock?.let { if (it.isHeld) it.release() }
        Log.d(TAG, "Service destroyed — START_STICKY will restart")
    }
}
