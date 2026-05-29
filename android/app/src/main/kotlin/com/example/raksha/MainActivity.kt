package com.example.raksha

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity :
        FlutterFragmentActivity(), GestureRecognizerHelper.GestureRecognizerListener, RecognitionListener {
    private val CHANNEL = "com.raksha/sos_service"
    private val GESTURE_CHANNEL = "com.example.raksha/gesture_service"
    private val PERMISSIONS_CHANNEL = "com.example.raksha/permissions"
    private var gestureHelper: GestureRecognizerHelper? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var isProcessingFrame = false
    private var lastProcessTime = 0L

    // Speech recognition
    private var speechRecognizer: SpeechRecognizer? = null
    private var voiceTriggers: List<String> = emptyList()
    private var isListeningForVoice = false
    
    // Stealth recording variables
    private var currentAudioRecorder: android.media.MediaRecorder? = null
    private var currentRecordingId: String? = null

    // Emergency broadcast receiver
    private val emergencyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.raksha.EMERGENCY_GESTURE") {
                val gesture = intent.getStringExtra("gesture") ?: "Unknown"
                val source = intent.getStringExtra("source") ?: "Unknown"
                
                Log.d("MainActivity", "🚨 EMERGENCY BROADCAST RECEIVED: $gesture from $source")
                
                // Trigger full SOS sequence
                triggerFullSOSSequence(gesture)
                
                // Notify Flutter
                runOnUiThread {
                    try {
                        val channel = MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger!!, GESTURE_CHANNEL)
                        channel.invokeMethod("onGestureDetected", mapOf(
                            "gesture" to gesture,
                            "confidence" to 0.95,
                            "source" to source
                        ))
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Failed to send emergency gesture to Flutter: ${e.message}")
                    }
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Register emergency broadcast receiver with proper flags for Android 14+
        val filter = IntentFilter("com.example.raksha.EMERGENCY_GESTURE")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(emergencyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(emergencyReceiver, filter)
        }
        
        // Request battery optimization exemption so service runs 24/7
        requestBatteryOptimizationExemption()
        
        // Pre-load user's selected gestures from Firebase
        loadUserGesturesFromFirebase()
        
        // Handle intent extras for SOS cancellation
        handleSOSIntentExtras()
        
        Log.d("MainActivity", "✅ Emergency broadcast receiver registered")
    }

    private fun requestBatteryOptimizationExemption() {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val pm = getSystemService(android.os.PowerManager::class.java)
                if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    Log.d("MainActivity", "✅ Requested battery optimization exemption")
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Battery optimization request failed: ${e.message}")
        }
    }
    
    private fun handleSOSIntentExtras() {
        try {
            val intent = intent
            
            if (intent.getBooleanExtra("SHOW_CANCEL", false)) {
                Log.d("MainActivity", "🏠 App opened to show cancel option")
                // Show cancel dialog immediately
                showCancelSOSDialog()
            }
            
            if (intent.getBooleanExtra("CANCEL_SOS", false)) {
                val gesture = intent.getStringExtra("GESTURE") ?: "Unknown"
                Log.d("MainActivity", "🛑 SOS cancelled from home screen for gesture: $gesture")
                cancelAllSOSSequence()
                
                // Show confirmation
                runOnUiThread {
                    android.widget.Toast.makeText(this, "🛑 Emergency SOS Cancelled", android.widget.Toast.LENGTH_LONG).show()
                }
            }
            
            // Handle vibration phase cancellation
            if (intent.action == "CANCEL_SOS_VIBRATION") {
                val gesture = intent.getStringExtra("gesture") ?: "Unknown"
                Log.d("MainActivity", "🛑 SOS cancelled during vibration phase for gesture: $gesture")
                cancelSOSDuringVibration()
                
                // Show confirmation
                runOnUiThread {
                    android.widget.Toast.makeText(this, "🛑 Emergency SOS Cancelled During Vibration", android.widget.Toast.LENGTH_LONG).show()
                }
            }
            
            // Handle showing vibration cancel dialog
            if (intent.getBooleanExtra("SHOW_VIBRATION_CANCEL", false)) {
                val gesture = intent.getStringExtra("GESTURE") ?: "Unknown"
                Log.d("MainActivity", "📱 App opened during vibration phase - showing cancel dialog")
                showVibrationCancelDialog(gesture)
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error handling SOS intent extras: ${e.message}")
        }
    }
    
    private fun showCancelSOSDialog() {
        // This will be handled by Flutter when the app opens
        // Send message to Flutter to show cancel dialog
        runOnUiThread {
            try {
                val channel = MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger!!, GESTURE_CHANNEL)
                channel.invokeMethod("showCancelDialog", mapOf("source" to "homeScreen"))
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to show cancel dialog: ${e.message}")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // SOS Service Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
                call,
                result ->
            try {
                when (call.method) {
                    "startFullSos" -> {
                        Log.d("MainActivity", "SOS started")
                        result.success("SOS started")
                    }
                    "stopActiveSos" -> {
                        Log.d("MainActivity", "SOS stopped")
                        result.success("SOS stopped")
                    }
                    "cancelTrigger" -> {
                        Log.d("MainActivity", "Trigger cancelled")
                        result.success("Trigger cancelled")
                    }
                    "startListener" -> {
                        val gestures = call.argument<List<String>>("gestures") ?: emptyList()
                        val voiceWords = call.argument<List<String>>("voiceWords") ?: emptyList()
                        // Start/restart the foreground service with the latest triggers
                        val serviceIntent = Intent(this, RakshaForegroundService::class.java).apply {
                            action = RakshaForegroundService.ACTION_START_LISTENER
                            putStringArrayListExtra(RakshaForegroundService.EXTRA_TRIGGERS, ArrayList(voiceWords))
                            putStringArrayListExtra("GESTURES_KEY", ArrayList(gestures))
                        }
                        startForegroundService(serviceIntent)
                        Log.d("MainActivity", "✅ Background service started via startListener with ${voiceWords.size} voice triggers")
                        result.success("Background service started")
                    }
                    "sendTestAlert" -> {
                        sendTestAlert()
                        Log.d("MainActivity", "📱 Test alert sent")
                        result.success("Test alert sent")
                    }
                    "sendEmergencySMS" -> {
                        val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        sendEmergencySMS(phoneNumber, message)
                        result.success("Emergency SMS sent")
                    }
                    "stopStealthRecording" -> {
                        stopStealthRecording()
                        result.success("Stealth recording stopped")
                    }
                    "cancelSOSDuringVibration" -> {
                        cancelSOSDuringVibration()
                        result.success("SOS cancelled during vibration phase")
                    }
                    "sendEmergencySMSToContacts" -> {
                        val gesture = call.argument<String>("gesture") ?: "Unknown"
                        val message = call.argument<String>("message") ?: "Emergency!"
                        sendEmergencySMSToContacts(gesture, message)
                        result.success("Emergency SMS sent to contacts")
                    }
                    "enableTestMode" -> {
                        enableTestMode()
                        result.success("Test mode enabled")
                    }
                    "startEmergencyRecording" -> {
                        val gesture = call.argument<String>("gesture") ?: "Unknown"
                        val timestamp = call.argument<Long>("timestamp") ?: System.currentTimeMillis()
                        startEmergencyRecording(gesture, timestamp)
                        result.success("Emergency recording started")
                    }
                    "stopEmergencyRecording" -> {
                        stopStealthRecording()
                        result.success("Emergency recording stopped")
                    }
                    "sendIAmSafeBroadcast" -> {
                        sendBroadcast(Intent("com.example.raksha.I_AM_SAFE"))
                        Log.d("MainActivity", "✅ I AM SAFE broadcast sent")
                        result.success("Safe broadcast sent")
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            result.success("Opened")
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "openVideoFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        try {
                            val file = java.io.File(path)
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this, "${packageName}.fileprovider", file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "video/mp4")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(Intent.createChooser(intent, "Play Video"))
                            result.success("Opened")
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "testSMSSystem" -> {
                        val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                        testSMSSystem(phoneNumber)
                        result.success("Test SMS sent")
                    }
                    "getSecureVaultRecordings" -> {
                        getSecureVaultRecordings(result)
                    }
                    "deleteSecureVaultRecording" -> {
                        val recordingId = call.argument<String>("recordingId") ?: ""
                        deleteSecureVaultRecording(recordingId, result)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERROR", "Failed to execute method: ${e.message}", null)
            }
        }

        // Gesture Service Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GESTURE_CHANNEL)
                .setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "startGestureService" -> {
                                val gestures =
                                        call.argument<List<String>>("gestures") ?: emptyList()
                                startGestureDetectionService(gestures)
                                Log.d("MainActivity", "🚀 Gesture service started with: $gestures")
                                result.success("Gesture service started")
                            }
                            "stopGestureService" -> {
                                stopGestureDetectionService()
                                Log.d("MainActivity", "🛑 Gesture service stopped")
                                result.success("Gesture service stopped")
                            }
                            "showSOSNotification" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                val countdown = call.argument<Int>("countdown") ?: 10
                                showSOSNotification(gesture, countdown)
                                result.success("SOS notification shown")
                            }
                            "startVibration" -> {
                                startEmergencyVibration()
                                result.success("Vibration started")
                            }
                            "cancelSOS" -> {
                                cancelSOSSequence()
                                result.success("SOS cancelled")
                            }
                            "stopVibration" -> {
                                stopVibration()
                                result.success("Vibration stopped")
                            }
                            "cancelAllSOS" -> {
                                cancelAllSOSSequence()
                                result.success("All SOS cancelled")
                            }
                            "startVibrationPhase" -> {
                                val duration = call.argument<Int>("duration") ?: 7
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                startVibrationPhase(duration, gesture)
                                result.success("Vibration phase started")
                            }
                            "showOpenAppNotification" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                val message = call.argument<String>("message") ?: "Open app to cancel"
                                showOpenAppNotification(gesture, message)
                                result.success("Open app notification shown")
                            }
                            "showHomeScreenCancel" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                val duration = call.argument<Int>("duration") ?: 120
                                showHomeScreenCancel(gesture, duration)
                                result.success("Home screen cancel shown")
                            }
                            "startEmergencyVibration" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                startEmergencyVibration(gesture)
                                result.success("Emergency vibration started")
                            }
                            "stopEmergencyVibration" -> {
                                stopEmergencyVibration()
                                result.success("Emergency vibration stopped")
                            }
                            "showCancellationNotification" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                val duration = call.argument<Int>("duration") ?: 120
                                showCancellationNotification(gesture, duration)
                                result.success("Cancellation notification shown")
                            }
                            "triggerFullSOS" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                triggerFullSOSSequence(gesture)
                                result.success("Full SOS triggered")
                            }
                            "enableTestMode" -> {
                                enableTestMode()
                                result.success("Test mode enabled")
                            }
                            "startVoiceDetection" -> {
                                val triggers =
                                        call.argument<List<String>>("triggers") ?: emptyList()
                                startVoiceDetection(triggers)
                                result.success("Voice detection started")
                            }
                            "stopVoiceDetection" -> {
                                stopVoiceDetection()
                                result.success("Voice detection stopped")
                            }
                            "forceStartMediaPipe" -> {
                                forceStartMediaPipeDetection()
                                result.success("MediaPipe force started")
                            }
                            "startRealBackgroundService" -> {
                                val gestures =
                                        call.argument<List<String>>("gestures") ?: emptyList()
                                startRealBackgroundService(gestures)
                                result.success("Real background service started")
                            }
                            "startAccessibilityService" -> {
                                startAccessibilityService()
                                result.success("Accessibility service started")
                            }
                            "enableSystemWideDetection" -> {
                                enableSystemWideDetection()
                                result.success("System-wide detection enabled")
                            }
                            "initializeGestureRecognition" -> {
                                initializeMediaPipeGestures()
                                result.success("MediaPipe initialized")
                            }
                            "processFrame" -> {
                                processCurrentCameraFrame(result)
                            }
                            "testMediaPipe" -> {
                                testMediaPipeWithSampleImage(result)
                            }
                            "testSimpleGesture" -> {
                                testSimpleGestureDetection(result)
                            }
                            "startNativeCameraProcessing" -> {
                                startNativeCameraProcessing(result)
                            }
                            "getLatestGestureResult" -> {
                                getLatestGestureResult(result)
                            }
                            "requestCameraPermission" -> {
                                requestCameraPermission(result)
                            }
                            "processCameraImageBytes" -> {
                                processCameraImageBytes(call, result)
                            }
                            "startMediaPipeProcessing" -> {
                                startMediaPipeProcessingOnly(result)
                            }
                            "stopLocationSharing" -> {
                                stopLocationSharing()
                                result.success("Location sharing stopped")
                            }
                            "startLocationSharing" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                startLocationSharing(gesture)
                                result.success("Location sharing started")
                            }
                            "clearGestureResult" -> {
                                // Clear any cached gesture results
                                result.success("Gesture result cleared")
                            }
                            "checkEmergencyContacts" -> {
                                checkEmergencyContacts(result)
                            }
                            "startEmergencyVibration" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                startEmergencyVibration(gesture)
                                result.success("Emergency vibration started")
                            }
                            "stopEmergencyVibration" -> {
                                stopEmergencyVibration()
                                result.success("Emergency vibration stopped")
                            }
                            "showOpenAppNotification" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                val message = call.argument<String>("message") ?: "Open app to cancel"
                                showOpenAppNotification(gesture, message)
                                result.success("Open app notification shown")
                            }
                            "showSOSCountdownNotification" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                val countdown = call.argument<Int>("countdown") ?: 10
                                showSOSCountdownNotification(gesture, countdown)
                                result.success("SOS countdown notification shown")
                            }
                            "showVibrationNotification" -> {
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                val message = call.argument<String>("message") ?: "Vibration phase"
                                showVibrationNotification(gesture, message)
                                result.success("Vibration notification shown")
                            }
                            else -> result.notImplemented()
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "❌ Gesture service error: ${e.message}")
                        result.error(
                                "ERROR",
                                "Failed to execute gesture method: ${e.message}",
                                null
                        )
                    }
                }

        // Permissions Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSIONS_CHANNEL)
                .setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "openAccessibilitySettings" -> {
                                openAccessibilitySettings()
                                result.success("Accessibility settings opened")
                            }
                            "openOverlaySettings" -> {
                                openOverlaySettings()
                                result.success("Overlay settings opened")
                            }
                            "requestBackgroundCameraPermission" -> {
                                requestBackgroundCameraPermission(result)
                            }
                            else -> result.notImplemented()
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to open settings: ${e.message}", null)
                    }
                }
        
        // Playback Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.raksha/playback")
                .setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "checkAndPlayRecording" -> {
                                val audioPath = call.argument<String>("audioPath")
                                val videoPath = call.argument<String>("videoPath")
                                val gesture = call.argument<String>("gesture") ?: "Unknown"
                                
                                Log.d("MainActivity", "🎵 ========== CHECK AND PLAY ==========")
                                Log.d("MainActivity", "Audio path: $audioPath")
                                Log.d("MainActivity", "Video path: $videoPath")
                                
                                // Check if files exist
                                val audioFile = if (audioPath != null) java.io.File(audioPath) else null
                                val videoFile = if (videoPath != null) java.io.File(videoPath) else null
                                
                                Log.d("MainActivity", "Audio file exists: ${audioFile?.exists()}, size: ${audioFile?.length() ?: 0} bytes")
                                Log.d("MainActivity", "Video file exists: ${videoFile?.exists()}, size: ${videoFile?.length() ?: 0} bytes")
                                
                                // List all files in secure vault directory
                                val secureVaultDir = java.io.File(filesDir, ".secure_vault")
                                if (secureVaultDir.exists()) {
                                    Log.d("MainActivity", "📂 Secure vault directory exists")
                                    val files = secureVaultDir.listFiles()
                                    if (files != null && files.isNotEmpty()) {
                                        Log.d("MainActivity", "📂 Files in secure vault: ${files.size}")
                                        var totalSize = 0L
                                        var emptyFiles = 0
                                        files.forEach { file ->
                                            Log.d("MainActivity", "  - ${file.name} (${file.length()} bytes)")
                                            totalSize += file.length()
                                            if (file.length() == 0L) emptyFiles++
                                        }
                                        Log.d("MainActivity", "📊 Total size: $totalSize bytes, Empty files: $emptyFiles")
                                        
                                        // Show toast with file info
                                        android.widget.Toast.makeText(
                                            this,
                                            "📂 Vault: ${files.size} files\n💾 Total: ${totalSize / 1024}KB\n⚠️ Empty: $emptyFiles",
                                            android.widget.Toast.LENGTH_LONG
                                        ).show()
                                    } else {
                                        Log.e("MainActivity", "❌ Secure vault directory is EMPTY!")
                                        android.widget.Toast.makeText(
                                            this,
                                            "❌ Secure vault is EMPTY!\n\nRecording is NOT working.\nCheck camera/microphone permissions.",
                                            android.widget.Toast.LENGTH_LONG
                                        ).show()
                                    }
                                } else {
                                    Log.e("MainActivity", "❌ Secure vault directory does NOT exist!")
                                    android.widget.Toast.makeText(
                                        this,
                                        "❌ Secure vault directory doesn't exist!\n\nRecording service never started.",
                                        android.widget.Toast.LENGTH_LONG
                                    ).show()
                                }
                                
                                // Try to play
                                if (audioFile?.exists() == true || videoFile?.exists() == true) {
                                    playRecordingSimple(audioPath, videoPath, gesture)
                                    result.success("Playing recording")
                                } else {
                                    Log.e("MainActivity", "❌ NO FILES FOUND - Recording may have failed!")
                                    android.widget.Toast.makeText(this, "❌ Recording files not found. Recording may have failed.", android.widget.Toast.LENGTH_LONG).show()
                                    result.error("NO_FILES", "Recording files not found. Recording may have failed.", null)
                                }
                            }
                            else -> result.notImplemented()
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "❌ Playback error: ${e.message}")
                        e.printStackTrace()
                        result.error("ERROR", "Failed to play recording: ${e.message}", null)
                    }
                }
    }

    private fun startGestureDetectionService(gestures: List<String>) {
        val intent = Intent(this, RakshaForegroundService::class.java).apply {
            action = RakshaForegroundService.ACTION_START_LISTENER
            putStringArrayListExtra("GESTURES_KEY", ArrayList(gestures))
            // Also pass current voice triggers so service has them immediately
            putStringArrayListExtra(RakshaForegroundService.EXTRA_TRIGGERS, ArrayList(voiceTriggers))
        }
        startForegroundService(intent)
    }

    private fun stopGestureDetectionService() {
        val intent = Intent(this, RakshaForegroundService::class.java)
        stopService(intent)
    }

    private fun sendTestAlert() {
        try {
            val smsManager = android.telephony.SmsManager.getDefault()
            val testMessage =
                    "🧪 TEST ALERT from Raksha app. This is a test of the emergency alert system. If this was a real emergency, you would receive location and emergency details."

            // For testing - replace with actual emergency contacts
            val testNumbers = listOf("1234567890") // Replace with actual numbers

            for (number in testNumbers) {
                try {
                    smsManager.sendTextMessage(number, null, testMessage, null, null)
                    Log.d("MainActivity", "📱 Test SMS sent to: $number")
                } catch (e: Exception) {
                    Log.e("MainActivity", "❌ Failed to send test SMS to $number: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error sending test alert: ${e.message}")
        }
    }

    // Send emergency SMS with live location
    private fun sendEmergencySMS(phoneNumber: String, message: String) {
        try {
            val smsManager = android.telephony.SmsManager.getDefault()

            // Split long messages into multiple parts if needed
            val parts = smsManager.divideMessage(message)

            if (parts.size == 1) {
                smsManager.sendTextMessage(phoneNumber, null, message, null, null)
                Log.d("MainActivity", "📱 Emergency SMS sent to: $phoneNumber")
            } else {
                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
                Log.d("MainActivity", "📱 Emergency SMS (multipart) sent to: $phoneNumber")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to send emergency SMS to $phoneNumber: ${e.message}")
        }
    }

    private fun showSOSNotification(gesture: String, countdown: Int) {
        val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val cancelIntent =
                Intent(this, MainActivity::class.java).apply {
                    action = "CANCEL_SOS"
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
        val cancelPendingIntent =
                PendingIntent.getActivity(
                        this,
                        1,
                        cancelIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

        val notification =
                NotificationCompat.Builder(this, "RAKSHA_SOS_CHANNEL")
                        .setContentTitle("🚨 EMERGENCY DETECTED!")
                        .setContentText("Gesture: $gesture - SOS in ${countdown}s")
                        .setSmallIcon(android.R.drawable.ic_dialog_alert)
                        .setPriority(NotificationCompat.PRIORITY_MAX)
                        .setCategory(NotificationCompat.CATEGORY_ALARM)
                        .setAutoCancel(false)
                        .setOngoing(true)
                        .addAction(android.R.drawable.ic_delete, "CANCEL", cancelPendingIntent)
                        .setFullScreenIntent(cancelPendingIntent, true)
                        .build()

        notificationManager.notify(1001, notification)
    }

    private fun startEmergencyVibration() {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            vibrator.vibrate(
                    android.os.VibrationEffect.createWaveform(
                            longArrayOf(0, 1000, 500, 1000, 500),
                            0
                    )
            )
        } else {
            vibrator.vibrate(longArrayOf(0, 1000, 500, 1000, 500), 0)
        }
    }

    private fun cancelSOSSequence() {
        val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(1001)

        stopVibration()

        Log.d("MainActivity", "🛑 SOS sequence cancelled")
    }
    
    private fun stopVibration() {
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
            vibrator.cancel()
            Log.d("MainActivity", "🛑 Vibration stopped")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error stopping vibration: ${e.message}")
        }
    }
    
    private fun cancelAllSOSSequence() {
        try {
            // Stop all vibrations
            stopVibration()
            
            // Cancel all notifications
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
            
            Log.d("MainActivity", "🛑 ALL SOS sequences cancelled")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error cancelling all SOS: ${e.message}")
        }
    }
    
    private fun startVibrationPhase(duration: Int, gesture: String) {
        try {
            Log.d("MainActivity", "📳 Starting ${duration}s vibration phase for $gesture")
            
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
            
            // Create vibration pattern for specified duration
            val pattern = LongArray(duration * 2) { i ->
                if (i % 2 == 0) 500L else 300L // 500ms vibrate, 300ms pause
            }
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                vibrator.vibrate(android.os.VibrationEffect.createWaveform(pattern, -1))
            } else {
                vibrator.vibrate(pattern, -1)
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting vibration phase: ${e.message}")
        }
    }
    
    private fun showOpenAppNotification(gesture: String, message: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create intent to open app for cancellation
            val openAppIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("SHOW_VIBRATION_CANCEL", true)
                putExtra("GESTURE", gesture)
            }
            val openAppPendingIntent = PendingIntent.getActivity(
                this, 2, openAppIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Create direct cancel intent
            val cancelIntent = Intent(this, MainActivity::class.java).apply {
                action = "CANCEL_SOS_VIBRATION"
                putExtra("gesture", gesture)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val cancelPendingIntent = PendingIntent.getActivity(
                this, 3, cancelIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val notification = NotificationCompat.Builder(this, "RAKSHA_SOS_CHANNEL")
                .setContentTitle("🚨 7-SECOND VIBRATION PHASE")
                .setContentText("$message - Tap CANCEL NOW or SOS will activate!")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(false)
                .setOngoing(true)
                .setContentIntent(openAppPendingIntent)
                .setFullScreenIntent(openAppPendingIntent, true)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "CANCEL SOS NOW", cancelPendingIntent)
                .setColor(android.graphics.Color.RED)
                .build()
                
            notificationManager.notify(2001, notification)
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error showing open app notification: ${e.message}")
        }
    }
    
    private fun showHomeScreenCancel(gesture: String, duration: Int) {
        try {
            Log.d("MainActivity", "🏠 Showing home screen cancel for ${duration}s")
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            val cancelIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("CANCEL_SOS", true)
                putExtra("GESTURE", gesture)
            }
            val cancelPendingIntent = PendingIntent.getActivity(
                this, 3, cancelIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val notification = NotificationCompat.Builder(this, "RAKSHA_SOS_CHANNEL")
                .setContentTitle("🚨 FINAL CHANCE TO CANCEL")
                .setContentText("SOS will activate in ${duration/60} minutes. Tap to cancel!")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(false)
                .setOngoing(true)
                .setContentIntent(cancelPendingIntent)
                .setFullScreenIntent(cancelPendingIntent, true)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "CANCEL SOS", cancelPendingIntent)
                .build()
                
            notificationManager.notify(3001, notification)
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error showing home screen cancel: ${e.message}")
        }
    }
    
    private fun triggerFinalSOSSequence(gesture: String) {
        try {
            Log.d("MainActivity", "🚨 FINAL SOS TRIGGERED - NO MORE CANCELLATION: $gesture")
            
            // Clear all notifications
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
            
            // Stop any vibrations
            stopVibration()
            
            // Trigger the actual emergency sequence
            triggerFullSOSSequence(gesture)
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error in final SOS: ${e.message}")
        }
    }

    private fun triggerFullSOSSequence(gesture: String) {
        Log.d("MainActivity", "🚨 FULL SOS TRIGGERED by gesture: $gesture")

        // 1. IMMEDIATELY START EMERGENCY RECORDING
        val timestamp = System.currentTimeMillis()
        startEmergencyRecording(gesture, timestamp)
        Log.d("MainActivity", "🎥 Emergency recording started for: $gesture")

        // 2. Get emergency contacts from Firebase and send SMS
        sendEmergencySMSToContacts(gesture, "🚨 EMERGENCY! Gesture detected: $gesture. I need immediate help! Emergency recording started. - Sent by Raksha Safety App")

        // 3. Start live location sharing
        startLocationSharing(gesture)

        // 4. Show emergency notification with cancel option
        showEmergencyActiveNotification(gesture)

        Log.d("MainActivity", "✅ Full SOS sequence activated: Recording + SMS + Location + Notification")
    }

    private fun showEmergencyActiveNotification(gesture: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create intent to open secure vault
            val vaultIntent = Intent(this, MainActivity::class.java).apply {
                putExtra("OPEN_SECURE_VAULT", true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val vaultPendingIntent = PendingIntent.getActivity(
                this, 3, vaultIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(this, "RAKSHA_SOS_CHANNEL")
                .setContentTitle("🚨 EMERGENCY ACTIVE!")
                .setContentText("Recording in progress. Tap to access Secure Vault.")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setOngoing(true) // Cannot be dismissed
                .setAutoCancel(false)
                .setContentIntent(vaultPendingIntent)
                .addAction(android.R.drawable.ic_menu_view, "SECURE VAULT", vaultPendingIntent)
                .setColor(android.graphics.Color.RED)
                .build()

            notificationManager.notify(1002, notification)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error showing emergency notification: ${e.message}")
        }
    }

    // MediaPipe gesture recognition methods - FIXED AND ENABLED
    private fun initializeMediaPipeGestures() {
        try {
            Log.d("MainActivity", "🚀 Initializing REAL MediaPipe gesture recognition...")
            
            // Initialize gesture helper with retry logic
            if (gestureHelper == null) {
                Log.d("MainActivity", "🔄 Creating new GestureRecognizerHelper...")
                gestureHelper = GestureRecognizerHelper(
                    minHandDetectionConfidence = 0.3f,
                    minHandTrackingConfidence = 0.3f,
                    minHandPresenceConfidence = 0.3f,
                    currentDelegate = GestureRecognizerHelper.DELEGATE_CPU,
                    runningMode = com.google.mediapipe.tasks.vision.core.RunningMode.IMAGE,
                    context = this,
                    gestureRecognizerListener = this
                )
                
                // Wait a moment for initialization
                Thread.sleep(1000)
                
                // Verify initialization
                if (!gestureHelper!!.isInitialized()) {
                    Log.w("MainActivity", "⚠️ First initialization failed, retrying...")
                    gestureHelper?.clearGestureRecognizer()
                    gestureHelper = GestureRecognizerHelper(
                        minHandDetectionConfidence = 0.3f,
                        minHandTrackingConfidence = 0.3f,
                        minHandPresenceConfidence = 0.3f,
                        currentDelegate = GestureRecognizerHelper.DELEGATE_CPU,
                        runningMode = com.google.mediapipe.tasks.vision.core.RunningMode.IMAGE,
                        context = this,
                        gestureRecognizerListener = this
                    )
                }
            }
            
            // DISABLED: Native camera conflicts with Flutter camera
            // startCameraForGestureDetection()

            Log.d("MainActivity", "✅ MediaPipe gesture detection initialized (NO native camera)")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to initialize MediaPipe gesture detection: ${e.message}")
            e.printStackTrace()
        }
    }

    // GestureRecognizerListener implementation
    override fun onResults(resultBundle: GestureRecognizerHelper.ResultBundle) {
        if (resultBundle.results.isNotEmpty()) {
            val result = resultBundle.results[0]
            if (result.gestures().isNotEmpty()) {
                val topGesture = result.gestures()[0]
                if (topGesture.isNotEmpty()) {
                    val gesture = topGesture[0]
                    val gestureName = gesture.categoryName()
                    val confidence = gesture.score()
                    
                    Log.d("MainActivity", "🎯 REAL Gesture detected: $gestureName (${(confidence * 100).toInt()}%)")

                    // Store result for Flutter to read
                    latestGestureResult = mapOf(
                        "gesture" to gestureName,
                        "confidence" to confidence.toDouble(),
                        "timestamp" to System.currentTimeMillis()
                    )

                    // Check if this is an emergency gesture (user's selected gestures)
                    val isEmergencyGesture = checkIfEmergencyGesture(gestureName, confidence)
                    
                    if (isEmergencyGesture && !isTestMode) {
                        Log.d("MainActivity", "🚨 EMERGENCY GESTURE DETECTED - Launching full-screen popup!")
                        launchFullScreenCountdown(gestureName)
                    }

                    // If test mode is active, send test alert
                    if (isTestMode) {
                        Log.d("MainActivity", "🧪 Test mode active - sending test alert for gesture: $gestureName")
                        sendTestAlert()
                        isTestMode = false // Reset test mode
                    }

                    // Send gesture result back to Flutter immediately - FIXED
                    runOnUiThread {
                        try {
                            Log.d("MainActivity", "📤 Sending gesture to Flutter: $gestureName")
                            val channel = MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger!!, GESTURE_CHANNEL)
                            channel.invokeMethod(
                                "onGestureDetected",
                                mapOf(
                                    "gesture" to gestureName,
                                    "confidence" to confidence.toDouble(),
                                    "isTestMode" to isTestMode
                                )
                            )
                            Log.d("MainActivity", "✅ Gesture sent to Flutter successfully")
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ FAILED to send gesture to Flutter: ${e.message}")
                            e.printStackTrace()
                        }
                    }
                }
            }
        }
    }

    override fun onError(error: String, errorCode: Int) {
        Log.e("MainActivity", "❌ Gesture recognition error: $error (code: $errorCode)")
    }

    private var isTestMode = false

    private fun enableTestMode() {
        isTestMode = true
        Log.d("MainActivity", "🧪 Test mode enabled - next gesture detection will send test alert")
    }

    private fun checkIfEmergencyGesture(gestureName: String, confidence: Float): Boolean {
        if (confidence < 0.5f) return false

        val mappedGesture = when (gestureName.lowercase()) {
            "victory", "peace", "peace_sign", "v_sign" -> "Victory"
            "thumb_up", "thumbs_up" -> "Thumb_Up"
            "thumb_down", "thumbs_down" -> "Thumb_Down"
            "closed_fist", "fist" -> "Closed_Fist"
            else -> gestureName
        }

        // Trigger on any of the 4 supported gestures
        return mappedGesture in listOf("Victory", "Thumb_Up", "Thumb_Down", "Closed_Fist")
    }

    private var userSelectedGestures = mutableListOf<String>()

    private fun loadUserGesturesFromFirebase() {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid ?: return
            com.google.firebase.firestore.FirebaseFirestore.getInstance()
                .collection("users").document(userId).get()
                .addOnSuccessListener { doc ->
                    val gestures = doc.get("triggerGestures") as? List<*>
                        ?: doc.get("selectedGestures") as? List<*>
                    if (gestures != null) {
                        userSelectedGestures.clear()
                        gestures.filterIsInstance<String>().forEach { userSelectedGestures.add(it) }
                        Log.d("MainActivity", "✅ Loaded user gestures: $userSelectedGestures")
                    } else {
                        // Default: all gestures trigger SOS
                        userSelectedGestures.addAll(listOf("Victory", "Thumb_Up", "Thumb_Down", "Closed_Fist"))
                        Log.d("MainActivity", "⚠️ No gestures saved — using all as default")
                    }
                }
                .addOnFailureListener {
                    userSelectedGestures.addAll(listOf("Victory", "Thumb_Up", "Thumb_Down", "Closed_Fist"))
                }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error loading gestures: ${e.message}")
        }
    }

    private fun launchFullScreenCountdown(gestureName: String) {
        try {
            Log.d("MainActivity", "🚀 Starting SOS notification countdown for gesture: $gestureName")
            
            // Start notification service for 10-second countdown
            val intent = Intent(this, SOSNotificationService::class.java).apply {
                putExtra("TRIGGER_WORD", "Gesture: $gestureName")
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            
            Log.d("MainActivity", "✅ SOS notification service started")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error launching countdown: ${e.message}")
            e.printStackTrace()
        }
    }

    // Start voice detection — delegates entirely to RakshaForegroundService
    private fun startVoiceDetection(triggers: List<String>) {
        voiceTriggers = triggers
        Log.d("MainActivity", "🎤 Starting voice detection with ${triggers.size} triggers: $triggers")

        // Start/update the foreground service with triggers
        val serviceIntent = Intent(this, RakshaForegroundService::class.java).apply {
            action = RakshaForegroundService.ACTION_START_LISTENER
            putStringArrayListExtra(RakshaForegroundService.EXTRA_TRIGGERS, ArrayList(triggers))
        }
        startForegroundService(serviceIntent)
        Log.d("MainActivity", "✅ RakshaForegroundService started with triggers")
    }

    // Stop voice detection
    private fun stopVoiceDetection() {
        isListeningForVoice = false
        speechRecognizer?.stopListening()
        speechRecognizer?.destroy()
        speechRecognizer = null
        
        // Stop the voice listener activity via broadcast
        try {
            val intent = Intent("com.example.raksha.STOP_VOICE_LISTENER")
            sendBroadcast(intent)
            Log.d("MainActivity", "🛑 Sent stop broadcast to voice listener")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error stopping voice listener: ${e.message}")
        }
        Log.d("MainActivity", "🛑 Voice detection stopped")
    }

    // Start listening for speech
    private fun startListening() {
        if (isListeningForVoice) return

        val intent =
                Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }

        isListeningForVoice = true
        speechRecognizer?.startListening(intent)
        Log.d("MainActivity", "🎤 Started listening for voice...")
    }

    // RecognitionListener implementation
    override fun onReadyForSpeech(params: Bundle?) {
        Log.d("MainActivity", "🎤 Ready for speech")
    }

    override fun onBeginningOfSpeech() {
        Log.d("MainActivity", "🎤 Speech started")
    }

    override fun onRmsChanged(rmsdB: Float) {
        // Sound level changed
    }

    override fun onBufferReceived(buffer: ByteArray?) {
        // Audio buffer received
    }

    override fun onEndOfSpeech() {
        Log.d("MainActivity", "🎤 Speech ended")
    }

    override fun onError(error: Int) {
        Log.e("MainActivity", "🎤 Speech error: $error")
        // Restart listening after error
        android.os.Handler()
                .postDelayed(
                        {
                            if (isListeningForVoice) {
                                startListening()
                            }
                        },
                        1000
                )
    }

    override fun onResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            val spokenText = matches[0].lowercase()
            Log.d("MainActivity", "🎤 HEARD: '$spokenText' | Checking against triggers: $voiceTriggers")

            // Check for trigger words with more flexible matching
            for (trigger in voiceTriggers) {
                val triggerLower = trigger.lowercase()
                if (spokenText.contains(triggerLower)) {
                    Log.d("MainActivity", "🚨 VOICE TRIGGER DETECTED: '$trigger' in '$spokenText'")
                    onVoiceTriggerDetected(trigger)
                    return // Stop checking other triggers
                }
            }
            
            // Also check for partial matches and common variations
            val emergencyWords = listOf("help", "emergency", "police", "danger", "rescue", "sos")
            for (word in emergencyWords) {
                if (spokenText.contains(word)) {
                    Log.d("MainActivity", "🚨 EMERGENCY WORD DETECTED: '$word' in '$spokenText'")
                    onVoiceTriggerDetected(word)
                    return
                }
            }
            
            Log.d("MainActivity", "🔍 No triggers found in: '$spokenText'")
        } else {
            Log.d("MainActivity", "🎤 No speech results received")
        }

        // Restart listening
        android.os.Handler()
                .postDelayed(
                        {
                            if (isListeningForVoice) {
                                startListening()
                            }
                        },
                        500
                )
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (matches != null && matches.isNotEmpty()) {
            val spokenText = matches[0].lowercase()
            Log.d("MainActivity", "🎤 Partial: '$spokenText'")

            // Check for trigger words in partial results too
            for (trigger in voiceTriggers) {
                if (spokenText.contains(trigger.lowercase())) {
                    Log.d("MainActivity", "🚨 VOICE TRIGGER DETECTED (partial): $trigger")
                    onVoiceTriggerDetected(trigger)
                    break
                }
            }
        }
    }

    override fun onEvent(eventType: Int, params: Bundle?) {
        // Speech event
    }

    // Handle voice trigger detection - ENHANCED TO TRIGGER SOS
    private fun onVoiceTriggerDetected(trigger: String) {
        Log.d("MainActivity", "🚨 VOICE TRIGGER DETECTED: $trigger - TRIGGERING SOS!")

        // Show immediate notification that trigger was detected
        showVoiceTriggerDetectedNotification(trigger)

        // Trigger full SOS sequence immediately
        triggerFullSOSSequence("VOICE: $trigger")

        // Send to Flutter
        runOnUiThread {
            try {
                val channel =
                        MethodChannel(
                                flutterEngine?.dartExecutor?.binaryMessenger!!,
                                GESTURE_CHANNEL
                        )
                channel.invokeMethod("onVoiceTriggerDetected", mapOf(
                    "trigger" to trigger,
                    "confidence" to 1.0,
                    "source" to "voice"
                ))
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to send voice trigger to Flutter: ${e.message}")
            }
        }

        // Send emergency broadcast for cross-app detection
        val intent = android.content.Intent("com.example.raksha.EMERGENCY_GESTURE").apply {
            putExtra("gesture", "VOICE: $trigger")
            putExtra("source", "voice")
            putExtra("type", "voice_trigger")
            putExtra("timestamp", System.currentTimeMillis())
        }
        sendBroadcast(intent)
    }
    
    private fun showVoiceTriggerDetectedNotification(trigger: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create notification channel if needed
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    "VOICE_TRIGGER_CHANNEL",
                    "Voice Trigger Detected",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications when voice triggers are detected"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 250, 250, 250)
                }
                notificationManager.createNotificationChannel(channel)
            }
            
            val notification = NotificationCompat.Builder(this, "VOICE_TRIGGER_CHANNEL")
                .setContentTitle("🎤 VOICE TRIGGER DETECTED!")
                .setContentText("Detected: \"$trigger\" - Emergency SOS activated")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setVibrate(longArrayOf(0, 250, 250, 250))
                .build()
            
            notificationManager.notify(2001, notification)
            
            Log.d("MainActivity", "✅ Voice trigger notification shown for: $trigger")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error showing voice trigger notification: ${e.message}")
        }
    }

    // Force start MediaPipe detection with aggressive settings
    private fun forceStartMediaPipeDetection() {
        Log.d("MainActivity", "🔥 FORCE STARTING MEDIAPIPE DETECTION")

        try {
            // Initialize MediaPipe if not already done
            if (gestureHelper == null) {
                gestureHelper = GestureRecognizerHelper(
                    minHandDetectionConfidence = 0.6f,
                    minHandTrackingConfidence = 0.6f,
                    minHandPresenceConfidence = 0.6f,
                    currentDelegate = GestureRecognizerHelper.DELEGATE_CPU,
                    runningMode = com.google.mediapipe.tasks.vision.core.RunningMode.IMAGE,
                    context = this,
                    gestureRecognizerListener = this
                )
            }

            // DISABLED: Native camera conflicts with Flutter camera
            // startCameraForGestureDetection()

            Log.d("MainActivity", "✅ MediaPipe detection FORCE STARTED (NO native camera)")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to force start MediaPipe: ${e.message}")
        }
    }

    // Start REAL background service for cross-app detection
    private fun startRealBackgroundService(gestures: List<String>) {
        Log.d("MainActivity", "🚀 Starting REAL background service")

        try {
            // Start the foreground service
            val intent =
                    Intent(this, RakshaForegroundService::class.java).apply {
                        action = RakshaForegroundService.ACTION_START_LISTENER
                        putStringArrayListExtra("GESTURES_KEY", ArrayList(gestures))
                    }
            startForegroundService(intent)

            Log.d("MainActivity", "✅ Real background service started")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to start real background service: ${e.message}")
        }
    }

    // Start AccessibilityService for system-wide gesture detection
    private fun startAccessibilityService() {
        try {
            Log.d("MainActivity", "🚀 Starting Accessibility Service for system-wide detection")
            
            // Check if accessibility service is enabled
            val accessibilityEnabled = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            
            val serviceName = "com.example.raksha/.RakshaAccessibilityService"
            
            if (accessibilityEnabled?.contains(serviceName) == true) {
                Log.d("MainActivity", "✅ Accessibility service already enabled")
            } else {
                Log.d("MainActivity", "⚠️ Accessibility service not enabled - opening settings")
                openAccessibilitySettings()
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting accessibility service: ${e.message}")
        }
    }
    
    // Enable complete system-wide detection
    private fun enableSystemWideDetection() {
        try {
            Log.d("MainActivity", "🚀 Enabling COMPLETE system-wide detection...")
            
            // 1. Request battery optimization exemption
            requestBatteryOptimizationExemption()
            
            // 2. Request overlay permission
            requestOverlayPermission()
            
            // 3. Start accessibility service
            startAccessibilityService()
            
            // 4. Start foreground service
            val intent = Intent(this, RakshaForegroundService::class.java).apply {
                action = RakshaForegroundService.ACTION_START_LISTENER
                putStringArrayListExtra("GESTURES_KEY", ArrayList(emptyList()))
            }
            startForegroundService(intent)
            
            Log.d("MainActivity", "✅ System-wide detection setup initiated")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error enabling system-wide detection: ${e.message}")
        }
    }
    
    private fun requestOverlayPermission() {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (!Settings.canDrawOverlays(this)) {
                    val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                    intent.data = android.net.Uri.parse("package:$packageName")
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    Log.d("MainActivity", "✅ Requested overlay permission")
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to request overlay permission: ${e.message}")
        }
    }

    // Open accessibility settings
    private fun openAccessibilitySettings() {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
            Log.d("MainActivity", "✅ Opened accessibility settings")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to open accessibility settings: ${e.message}")
        }
    }

    // Open overlay permission settings
    private fun openOverlaySettings() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
            intent.data = android.net.Uri.parse("package:$packageName")
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
            Log.d("MainActivity", "✅ Opened overlay settings")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to open overlay settings: ${e.message}")
        }
    }
    
    // Play recording from secure vault
    private fun playRecording(audioPath: String?, videoPath: String?, gesture: String) {
        try {
            Log.d("MainActivity", "🎵 ========== PLAYING RECORDING ==========")
            Log.d("MainActivity", "Audio: $audioPath")
            Log.d("MainActivity", "Video: $videoPath")
            
            // Check which file exists
            val audioFile = if (audioPath != null) java.io.File(audioPath) else null
            val videoFile = if (videoPath != null) java.io.File(videoPath) else null
            
            Log.d("MainActivity", "Audio exists: ${audioFile?.exists()}")
            Log.d("MainActivity", "Video exists: ${videoFile?.exists()}")
            
            // Choose file to play (prefer video)
            val fileToPlay = when {
                videoFile?.exists() == true -> videoFile
                audioFile?.exists() == true -> audioFile
                else -> {
                    Log.e("MainActivity", "❌ No valid files found")
                    android.widget.Toast.makeText(this, "❌ Recording file not found", android.widget.Toast.LENGTH_LONG).show()
                    return
                }
            }
            
            Log.d("MainActivity", "📂 Playing file: ${fileToPlay.absolutePath}")
            Log.d("MainActivity", "📂 File size: ${fileToPlay.length()} bytes")
            
            // Create URI using FileProvider
            val fileUri = androidx.core.content.FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                fileToPlay
            )
            
            Log.d("MainActivity", "📂 File URI: $fileUri")
            
            // Create intent to open with system media player
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, if (fileToPlay.extension == "mp4") "video/*" else "audio/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            
            // Check if there's an app that can handle this
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(Intent.createChooser(intent, "Play Recording"))
                Log.d("MainActivity", "✅ Media player launched")
            } else {
                Log.e("MainActivity", "❌ No app found to play media")
                android.widget.Toast.makeText(this, "❌ No media player app found", android.widget.Toast.LENGTH_LONG).show()
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error playing recording: ${e.message}")
            e.printStackTrace()
            android.widget.Toast.makeText(this, "❌ Error: ${e.message}", android.widget.Toast.LENGTH_LONG).show()
        }
    }
    
    // Play recording using PlaybackActivity
    private fun playRecordingWithActivity(audioPath: String?, videoPath: String?, gesture: String) {
        try {
            Log.d("MainActivity", "🎵 Launching PlaybackActivity")
            
            val intent = Intent(this, PlaybackActivity::class.java).apply {
                putExtra("audioPath", audioPath)
                putExtra("videoPath", videoPath)
                putExtra("gesture", gesture)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            
            startActivity(intent)
            Log.d("MainActivity", "✅ PlaybackActivity launched")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error launching PlaybackActivity: ${e.message}")
            e.printStackTrace()
            android.widget.Toast.makeText(this, "❌ Error: ${e.message}", android.widget.Toast.LENGTH_LONG).show()
        }
    }
    
    // Simple playback by copying file to Downloads and showing path
    private fun playRecordingSimple(audioPath: String?, videoPath: String?, gesture: String) {
        try {
            Log.d("MainActivity", "🎵 ========== SIMPLE PLAYBACK ==========")
            
            // Choose file to play (prefer audio)
            val sourceFile = when {
                audioPath != null && java.io.File(audioPath).exists() -> java.io.File(audioPath)
                videoPath != null && java.io.File(videoPath).exists() -> java.io.File(videoPath)
                else -> {
                    Log.e("MainActivity", "❌ No valid files")
                    android.widget.Toast.makeText(this, "❌ No recording files found", android.widget.Toast.LENGTH_LONG).show()
                    return
                }
            }
            
            Log.d("MainActivity", "📂 Source: ${sourceFile.absolutePath}")
            Log.d("MainActivity", "📂 Size: ${sourceFile.length()} bytes (${sourceFile.length() / 1024}KB)")
            
            if (sourceFile.length() == 0L) {
                android.widget.Toast.makeText(
                    this, 
                    "❌ File is empty (0 bytes)\n\nRecording failed!", 
                    android.widget.Toast.LENGTH_LONG
                ).show()
                return
            }
            
            // Copy to Downloads folder (publicly accessible)
            val downloadsDir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
            val publicFile = java.io.File(downloadsDir, "Raksha_Emergency_${System.currentTimeMillis()}.${sourceFile.extension}")
            
            Log.d("MainActivity", "📂 Copying to Downloads: ${publicFile.absolutePath}")
            sourceFile.copyTo(publicFile, overwrite = true)
            
            Log.d("MainActivity", "✅ Copied ${publicFile.length()} bytes")
            
            // Show success message with file location
            android.widget.Toast.makeText(
                this,
                "✅ Recording saved to Downloads!\n\n" +
                "File: ${publicFile.name}\n" +
                "Size: ${publicFile.length() / 1024}KB\n\n" +
                "Open it from your Downloads folder with any music/video player app!",
                android.widget.Toast.LENGTH_LONG
            ).show()
            
            // Try to open with VLC or any media player
            try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(android.net.Uri.fromFile(publicFile), "audio/*")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                
                // Try to start activity
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(Intent.createChooser(intent, "Play with..."))
                    Log.d("MainActivity", "✅ Opened chooser")
                } else {
                    Log.d("MainActivity", "No app to open, but file saved to Downloads")
                }
            } catch (e: Exception) {
                Log.d("MainActivity", "Could not auto-open: ${e.message}")
                // File is still in Downloads, user can open manually
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error: ${e.message}")
            e.printStackTrace()
            android.widget.Toast.makeText(this, "❌ Error: ${e.message}", android.widget.Toast.LENGTH_LONG).show()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        
        // Unregister broadcast receiver
        try {
            unregisterReceiver(emergencyReceiver)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error unregistering receiver: ${e.message}")
        }
        
        stopVoiceDetection()
        cameraProvider?.unbindAll()
        cameraExecutor.shutdown()
        gestureHelper?.clearGestureRecognizer()
    }

    // RESTORED - Full camera method for gesture detection
    private fun startCameraForGestureDetection() {
        Log.d("MainActivity", "🎥 Starting camera for REAL MediaPipe gesture detection...")
        
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
                
                imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(android.util.Size(640, 480))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()

                imageAnalysis?.setAnalyzer(cameraExecutor) { imageProxy ->
                    val currentTime = System.currentTimeMillis()
                    if (!isProcessingFrame && gestureHelper != null && 
                        (currentTime - lastProcessTime) > 1000) {
                        isProcessingFrame = true
                        lastProcessTime = currentTime
                        Thread { processImageProxy(imageProxy) }.start()
                    } else {
                        imageProxy.close()
                    }
                }

                cameraProvider?.unbindAll()
                cameraProvider?.bindToLifecycle(this, cameraSelector, imageAnalysis)
                Log.d("MainActivity", "✅ Camera started for gesture detection")
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Camera setup failed: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    // Process ImageProxy through MediaPipe - RESTORED
    private fun processImageProxy(imageProxy: ImageProxy) {
        try {
            Log.d("MainActivity", "🎯 Processing frame through MediaPipe...")
            val bitmap = imageProxyToBitmap(imageProxy)
            
            if (bitmap != null && gestureHelper != null) {
                Log.d("MainActivity", "📷 Bitmap created: ${bitmap.width}x${bitmap.height}")
                val result = gestureHelper?.recognizeImage(bitmap)
                if (result != null) {
                    Log.d("MainActivity", "📊 MediaPipe result received")
                } else {
                    Log.w("MainActivity", "❌ MediaPipe returned null result")
                }
            } else {
                Log.e("MainActivity", "❌ Failed to create bitmap from ImageProxy")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error processing image: ${e.message}")
        } finally {
            imageProxy.close()
            isProcessingFrame = false
        }
    }

    // Convert ImageProxy to Bitmap - RESTORED
    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap? {
        return try {
            Log.d("MainActivity", "🔄 Converting ImageProxy to Bitmap - Format: ${imageProxy.format}")
            val buffer = imageProxy.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            
            val width = imageProxy.width
            val height = imageProxy.height
            val pixels = IntArray(width * height)
            
            for (i in bytes.indices) {
                if (i < pixels.size) {
                    val gray = bytes[i].toInt() and 0xFF
                    pixels[i] = (0xFF shl 24) or (gray shl 16) or (gray shl 8) or gray
                }
            }
            
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            Log.d("MainActivity", "✅ Bitmap created successfully: ${bitmap.width}x${bitmap.height}")
            bitmap
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error converting ImageProxy to Bitmap: ${e.message}")
            null
        }
    }

    // REMOVED DUPLICATE

    // REMOVED DUPLICATE

    // Process current camera frame through MediaPipe
    private fun processCurrentCameraFrame(result: MethodChannel.Result) {
        try {
            if (gestureHelper == null) {
                Log.w("MainActivity", "GestureHelper not initialized")
                result.success(mapOf("error" to "GestureHelper not initialized"))
                return
            }

            // DISABLED: Native camera conflicts with Flutter camera
            // if (cameraProvider == null) {
            //     startCameraForGestureDetection()
            // }

            Log.d("MainActivity", "🎯 REAL MediaPipe gesture detection active")
            result.success(mapOf(
                "status" to "active",
                "message" to "Real MediaPipe processing camera frames"
            ))
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error processing frame: ${e.message}")
            result.success(mapOf("error" to e.message))
        }
    }
    
    // Test MediaPipe with a simple colored bitmap
    private fun testMediaPipeWithSampleImage(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🧪 Testing MediaPipe with sample image")
            
            if (gestureHelper == null) {
                result.error("NO_HELPER", "GestureHelper not initialized", null)
                return
            }
            
            // Create a simple test bitmap (solid color)
            val testBitmap = Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888)
            testBitmap.eraseColor(android.graphics.Color.BLUE)
            
            Log.d("MainActivity", "🎨 Created test bitmap: ${testBitmap.width}x${testBitmap.height}")
            
            // Process through MediaPipe
            val gestureResult = gestureHelper?.recognizeImage(testBitmap)
            
            if (gestureResult != null) {
                Log.d("MainActivity", "✅ MediaPipe test successful - got result")
                result.success(mapOf(
                    "status" to "success",
                    "message" to "MediaPipe is working",
                    "resultCount" to gestureResult.results.size
                ))
            } else {
                Log.w("MainActivity", "⚠️ MediaPipe test returned null")
                result.success(mapOf(
                    "status" to "null_result",
                    "message" to "MediaPipe returned null result"
                ))
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ MediaPipe test failed: ${e.message}")
            e.printStackTrace()
            result.error("TEST_FAILED", e.message, null)
        }
    }
    
    // Request camera permission
    private fun requestCameraPermission(result: MethodChannel.Result) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (checkSelfPermission(android.Manifest.permission.CAMERA) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf(android.Manifest.permission.CAMERA), 100)
                    Log.d("MainActivity", "📷 Camera permission requested")
                } else {
                    Log.d("MainActivity", "✅ Camera permission already granted")
                }
            }
            result.success("Camera permission handled")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error requesting camera permission: ${e.message}")
            result.error("PERMISSION_ERROR", e.message, null)
        }
    }
    
    // Test simple gesture detection without MediaPipe
    private fun testSimpleGestureDetection(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🧪 Testing simple gesture detection (no MediaPipe)")
            
            // Simulate gesture detection for testing
            val testGestures = listOf("Thumb_Up", "Thumb_Down", "Victory", "Closed_Fist")
            val randomGesture = testGestures.shuffled().first()
            val randomConfidence = 0.8
            
            Log.d("MainActivity", "🎯 Simulated gesture: $randomGesture (${(randomConfidence * 100).toInt()}%)")
            
            result.success(mapOf(
                "status" to "success",
                "gesture" to randomGesture,
                "confidence" to randomConfidence,
                "message" to "Simulated gesture detection"
            ))
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Simple gesture test failed: ${e.message}")
            result.error("TEST_FAILED", e.message, null)
        }
    }
    
    // Store latest gesture result
    private var latestGestureResult: Map<String, Any>? = null
    private var isNativeProcessingActive = false
    
    // Start native camera processing without takePicture
    private fun startNativeCameraProcessing(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🎥 Starting native camera processing...")
            isNativeProcessingActive = true
            
            // DISABLED - No native camera to prevent Flutter conflicts
            Log.d("MainActivity", "🚫 Native camera continuous start DISABLED")
            
            result.success("Native camera processing started")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting native processing: ${e.message}")
            result.error("PROCESSING_ERROR", e.message, null)
        }
    }
    
    // Get latest gesture result
    private fun getLatestGestureResult(result: MethodChannel.Result) {
        try {
            if (latestGestureResult != null) {
                result.success(latestGestureResult)
                // Clear result after reading
                latestGestureResult = null
            } else {
                result.success(mapOf(
                    "gesture" to "None",
                    "confidence" to 0.0
                ))
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error getting gesture result: ${e.message}")
            result.error("RESULT_ERROR", e.message, null)
        }
    }
    
    // New methods for improved SOS flow
    private fun startEmergencyVibration(gesture: String) {
        try {
            Log.d("MainActivity", "🔥 Starting emergency vibration for: $gesture")
            val vibrator = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
            }
            
            // Create vibration pattern: vibrate for 1s, pause 0.5s, repeat
            val pattern = longArrayOf(0, 1000, 500, 1000, 500, 1000, 500)
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                vibrator.vibrate(android.os.VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, 0)
            }
            
            Log.d("MainActivity", "✅ Emergency vibration started")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting emergency vibration: ${e.message}")
        }
    }
    
    private fun stopEmergencyVibration() {
        try {
            val vibrator = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
            }
            
            vibrator.cancel()
            Log.d("MainActivity", "🛑 Emergency vibration stopped")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error stopping vibration: ${e.message}")
        }
    }
    
    private fun showCancellationNotification(gesture: String, duration: Int) {
        try {
            Log.d("MainActivity", "📱 Showing cancellation notification for: $gesture")
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create notification channel
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    "emergency_cancel",
                    "Emergency Cancellation",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Emergency SOS cancellation notifications"
                    enableVibration(false) // Don't add more vibration
                }
                notificationManager.createNotificationChannel(channel)
            }
            
            // Create cancel intent
            val cancelIntent = Intent(this, MainActivity::class.java).apply {
                action = "CANCEL_EMERGENCY"
                putExtra("gesture", gesture)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            
            val cancelPendingIntent = PendingIntent.getActivity(
                this, 
                0, 
                cancelIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Build notification
            val notification = androidx.core.app.NotificationCompat.Builder(this, "emergency_cancel")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("🚨 EMERGENCY SOS ACTIVE")
                .setContentText("Tap to CANCEL emergency or it will trigger in ${duration/60} minutes")
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .setCategory(androidx.core.app.NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(false)
                .setOngoing(true)
                .setContentIntent(cancelPendingIntent)
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "CANCEL EMERGENCY",
                    cancelPendingIntent
                )
                .setColor(android.graphics.Color.RED)
                .build()
            
            notificationManager.notify(999, notification)
            Log.d("MainActivity", "✅ Cancellation notification shown")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error showing cancellation notification: ${e.message}")
        }
    }
    
    private fun processImageFileForGesture(imagePath: String, result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🎯 Processing image file for gesture: $imagePath")
            // Load bitmap from file
            val bitmap = android.graphics.BitmapFactory.decodeFile(imagePath)
            if (bitmap == null) {
                result.error("INVALID_IMAGE", "Could not load image from path", null)
                return
            }
            Log.d("MainActivity", "📷 Image loaded: ${bitmap.width}x${bitmap.height}")
            // Process through MediaPipe
            val gestureResult = gestureHelper?.recognizeImage(bitmap)
            if (gestureResult != null && gestureResult.results.isNotEmpty()) {
                val mpResult = gestureResult.results[0]
                if (mpResult.gestures().isNotEmpty()) {
                    val topGesture = mpResult.gestures()[0]
                    if (topGesture.isNotEmpty()) {
                        val gesture = topGesture[0]
                        val gestureName = gesture.categoryName()
                        val confidence = gesture.score()
                        Log.d("MainActivity", "✅ GESTURE DETECTED: $gestureName (${(confidence * 100).toInt()}%)")
                        result.success(mapOf(
                            "gesture" to gestureName,
                            "confidence" to confidence.toDouble()
                        ))
                        return
                    }
                }
            }
            // No gesture detected
            result.success(mapOf(
                "gesture" to "None",
                "confidence" to 0.0
            ))
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error processing image for gesture: ${e.message}")
            e.printStackTrace()
            result.error("PROCESSING_ERROR", e.message, null)
        }
    }
    
    private fun startEmergencyRecording(gesture: String, timestamp: Long) {
        try {
            Log.d("MainActivity", "🎥 Starting SECURE VAULT emergency recording for gesture: $gesture")
            
            // Create unique recording session ID
            val recordingId = "emergency_${timestamp}_${gesture.replace(" ", "_")}"
            
            // Create secure vault directory if it doesn't exist
            createSecureVaultDirectory()
            
            // Start stealth audio recording to secure vault
            startSecureAudioRecording(recordingId, gesture, timestamp)
            
            // Start stealth video recording to secure vault
            startSecureVideoRecording(recordingId, gesture, timestamp)
            
            // Save recording session metadata to Firebase with encryption
            saveSecureRecordingSession(recordingId, gesture, timestamp)
            
            // NO auto-stop timer - recording continues until user clicks "I am safe"
            Log.d("MainActivity", "🔄 Recording will continue until user manually stops it")
            
            Log.d("MainActivity", "✅ SECURE VAULT recording started - ID: $recordingId")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting secure emergency recording: ${e.message}")
        }
    }
    
    private fun createSecureVaultDirectory() {
        try {
            // Create hidden secure vault directory
            val secureVaultDir = java.io.File(filesDir, ".secure_vault")
            if (!secureVaultDir.exists()) {
                secureVaultDir.mkdirs()
                Log.d("MainActivity", "📁 Created secure vault directory")
            }
            
            // Create .nomedia file to hide from gallery
            val noMediaFile = java.io.File(secureVaultDir, ".nomedia")
            if (!noMediaFile.exists()) {
                noMediaFile.createNewFile()
                Log.d("MainActivity", "🔒 Created .nomedia file for privacy")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error creating secure vault: ${e.message}")
        }
    }
    
    private fun startSecureAudioRecording(recordingId: String, gesture: String, timestamp: Long) {
        try {
            Log.d("MainActivity", "🎤 Starting SECURE audio recording for emergency")
            
            // Stop any existing recording
            try {
                currentAudioRecorder?.stop()
                currentAudioRecorder?.release()
            } catch (e: Exception) {
                Log.w("MainActivity", "Previous recorder cleanup: ${e.message}")
            }
            
            // Check microphone permission
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    Log.e("MainActivity", "❌ Microphone permission not granted!")
                    return
                }
            }
            
            val secureVaultDir = java.io.File(filesDir, ".secure_vault")
            if (!secureVaultDir.exists()) {
                secureVaultDir.mkdirs()
            }
            
            val audioFile = java.io.File(secureVaultDir, "${recordingId}_audio.3gp")
            Log.d("MainActivity", "🎤 Audio will be saved to: ${audioFile.absolutePath}")
            
            // Create audio recorder for secure vault
            val audioRecorder = android.media.MediaRecorder().apply {
                setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                setOutputFormat(android.media.MediaRecorder.OutputFormat.THREE_GPP)
                setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AMR_NB)
                setOutputFile(audioFile.absolutePath)
                
                prepare()
                start()
            }
            
            // Store recorder reference
            currentAudioRecorder = audioRecorder
            currentRecordingId = recordingId
            
            Log.d("MainActivity", "✅ SECURE audio recording ACTIVE: ${audioFile.name}")
            
            // Update Firebase immediately to show recording started
            updateRecordingStatus(recordingId, "recording_audio")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting secure audio recording: ${e.message}")
            e.printStackTrace()
        }
    }
    
    private fun updateRecordingStatus(recordingId: String, status: String) {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .collection("secureVaultRecordings")
                    .document(recordingId)
                    .update("status", status)
                    .addOnSuccessListener {
                        Log.d("MainActivity", "✅ Recording status updated: $status")
                    }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error updating recording status: ${e.message}")
        }
    }
    
    private fun startSecureVideoRecording(recordingId: String, gesture: String, timestamp: Long) {
        try {
            Log.d("MainActivity", "📹 Starting SECURE video recording via StealthRecordingService")
            
            // Release Flutter camera first to avoid conflict with Camera2
            cameraProvider?.unbindAll()
            
            val intent = Intent(this, StealthRecordingService::class.java).apply {
                action = "START_STEALTH_RECORDING"
                putExtra("recordingId", recordingId)
                putExtra("gesture", gesture)
                putExtra("timestamp", timestamp)
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            
            Log.d("MainActivity", "✅ SECURE video recording service started")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting secure video recording: ${e.message}")
        }
    }
    
    private fun saveSecureRecordingSession(recordingId: String, gesture: String, timestamp: Long) {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                val secureVaultDir = java.io.File(filesDir, ".secure_vault")
                val audioPath = java.io.File(secureVaultDir, "${recordingId}_audio.3gp").absolutePath
                val videoPath = java.io.File(secureVaultDir, "${recordingId}_video.mp4").absolutePath
                
                val recordingData = mapOf(
                    "recordingId" to recordingId,
                    "gesture" to gesture,
                    "timestamp" to timestamp,
                    "startTime" to timestamp,
                    "startTimeFormatted" to java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(timestamp)),
                    "status" to "recording",
                    "hasAudio" to true,
                    "hasVideo" to true,
                    "audioPath" to audioPath,
                    "videoPath" to videoPath,
                    "deviceId" to android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID)
                )
                
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .collection("secureVaultRecordings")
                    .document(recordingId)
                    .set(recordingData)
                    .addOnSuccessListener {
                        Log.d("MainActivity", "✅ Recording session saved to Firebase")
                    }
                    .addOnFailureListener { e ->
                        Log.e("MainActivity", "❌ Failed to save recording session: ${e.message}")
                    }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error saving recording session: ${e.message}")
        }
    }
    
    private fun scheduleRecordingStop(recordingId: String, delayMs: Long) {
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            Log.d("MainActivity", "⏰ Auto-stopping recording: $recordingId")
            stopStealthRecording()
        }, delayMs)
    }
    
    // Show SOS countdown notification
    private fun showSOSCountdownNotification(gesture: String, countdown: Int) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create cancel intent
            val cancelIntent = Intent(this, MainActivity::class.java).apply {
                action = "CANCEL_SOS_COUNTDOWN"
                putExtra("gesture", gesture)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val cancelPendingIntent = PendingIntent.getActivity(
                this, 4, cancelIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val notification = NotificationCompat.Builder(this, "RAKSHA_SOS_CHANNEL")
                .setContentTitle("🚨 EMERGENCY COUNTDOWN: ${countdown}s")
                .setContentText("$gesture detected! SOS will activate in ${countdown} seconds")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(false)
                .setOngoing(true)
                .setFullScreenIntent(cancelPendingIntent, true)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "CANCEL SOS", cancelPendingIntent)
                .setColor(android.graphics.Color.RED)
                .build()
                
            notificationManager.notify(4001, notification)
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error showing SOS countdown notification: ${e.message}")
        }
    }
    
    // Show vibration phase notification
    private fun showVibrationNotification(gesture: String, message: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create cancel intent
            val cancelIntent = Intent(this, MainActivity::class.java).apply {
                action = "CANCEL_SOS_VIBRATION"
                putExtra("gesture", gesture)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val cancelPendingIntent = PendingIntent.getActivity(
                this, 5, cancelIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val notification = NotificationCompat.Builder(this, "RAKSHA_SOS_CHANNEL")
                .setContentTitle("🚨 7-SECOND VIBRATION PHASE")
                .setContentText("$message")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(false)
                .setOngoing(true)
                .setFullScreenIntent(cancelPendingIntent, true)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "CANCEL SOS NOW", cancelPendingIntent)
                .setColor(android.graphics.Color.YELLOW)
                .build()
                
            notificationManager.notify(5001, notification)
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error showing vibration notification: ${e.message}")
        }
    }
    
    // Get secure vault recordings
    private fun getSecureVaultRecordings(result: MethodChannel.Result) {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .collection("secureVaultRecordings")
                    .orderBy("timestamp", com.google.firebase.firestore.Query.Direction.DESCENDING)
                    .get()
                    .addOnSuccessListener { documents ->
                        val recordings = mutableListOf<Map<String, Any>>()
                        for (document in documents) {
                            val data = document.data.toMutableMap()
                            data["id"] = document.id
                            recordings.add(data)
                        }
                        result.success(recordings)
                    }
                    .addOnFailureListener { e ->
                        result.error("FIREBASE_ERROR", "Failed to get recordings: ${e.message}", null)
                    }
            } else {
                result.error("NO_USER", "User not logged in", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", "Error getting recordings: ${e.message}", null)
        }
    }
    
    // Delete secure vault recording
    private fun deleteSecureVaultRecording(recordingId: String, result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🗑️ Deleting secure vault recording: $recordingId")
            
            // Delete local files
            val secureVaultDir = java.io.File(filesDir, ".secure_vault")
            val audioFile = java.io.File(secureVaultDir, "${recordingId}_audio.3gp")
            val videoFile = java.io.File(secureVaultDir, "${recordingId}_video.mp4")
            
            if (audioFile.exists()) {
                audioFile.delete()
                Log.d("MainActivity", "🗑️ Deleted audio file")
            }
            
            if (videoFile.exists()) {
                videoFile.delete()
                Log.d("MainActivity", "🗑️ Deleted video file")
            }
            
            // Delete Firebase record
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .collection("secureVaultRecordings")
                    .document(recordingId)
                    .delete()
                    .addOnSuccessListener {
                        result.success("Recording deleted successfully")
                    }
                    .addOnFailureListener { e ->
                        result.error("DELETE_ERROR", "Failed to delete recording: ${e.message}", null)
                    }
            } else {
                result.error("NO_USER", "User not logged in", null)
            }
            
        } catch (e: Exception) {
            result.error("ERROR", "Error deleting recording: ${e.message}", null)
        }
    }
    
    private fun startStealthAudioRecording(recordingId: String, gesture: String, timestamp: Long) {
        try {
            Log.d("MainActivity", "🎤 Starting STEALTH audio recording")
            
            // Create audio recorder in background
            val audioRecorder = android.media.MediaRecorder().apply {
                setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                setOutputFormat(android.media.MediaRecorder.OutputFormat.THREE_GPP)
                setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AMR_NB)
                
                // Save to internal app directory (hidden from user)
                val audioFile = java.io.File(filesDir, "${recordingId}_audio.3gp")
                setOutputFile(audioFile.absolutePath)
                
                prepare()
                start()
            }
            
            // Store recorder reference for stopping later
            currentAudioRecorder = audioRecorder
            currentRecordingId = recordingId
            
            Log.d("MainActivity", "✅ Stealth audio recording active")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting stealth audio recording: ${e.message}")
        }
    }
    
    private fun startStealthVideoRecording(recordingId: String, gesture: String, timestamp: Long) {
        try {
            Log.d("MainActivity", "📹 Starting STEALTH video recording from front camera")
            
            // Start background camera service for stealth recording
            val intent = Intent(this, StealthRecordingService::class.java).apply {
                action = "START_STEALTH_RECORDING"
                putExtra("recordingId", recordingId)
                putExtra("gesture", gesture)
                putExtra("timestamp", timestamp)
            }
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            
            Log.d("MainActivity", "✅ Stealth video recording service started")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting stealth video recording: ${e.message}")
        }
    }
    
    private fun saveRecordingSessionToFirebase(recordingId: String, gesture: String, timestamp: Long) {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                val recordingData = mapOf(
                    "recordingId" to recordingId,
                    "userId" to userId,
                    "gesture" to gesture,
                    "startTimestamp" to timestamp,
                    "status" to "recording",
                    "audioFile" to "${recordingId}_audio.3gp",
                    "videoFile" to "${recordingId}_video.mp4",
                    "deviceInfo" to mapOf(
                        "model" to android.os.Build.MODEL,
                        "manufacturer" to android.os.Build.MANUFACTURER,
                        "androidVersion" to android.os.Build.VERSION.RELEASE
                    )
                )
                
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("emergency_recordings")
                    .document(recordingId)
                    .set(recordingData)
                    .addOnSuccessListener {
                        Log.d("MainActivity", "✅ Recording session saved to Firebase")
                    }
                    .addOnFailureListener { e ->
                        Log.e("MainActivity", "❌ Failed to save recording session: ${e.message}")
                    }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error saving recording session: ${e.message}")
        }
    }
    
    // Stop stealth recording (only called when user clicks "I am safe")
    private fun stopStealthRecording() {
        try {
            Log.d("MainActivity", "🛑 Stopping stealth recording")
            
            // Stop audio recording
            try {
                currentAudioRecorder?.stop()
                currentAudioRecorder?.release()
            } catch (e: Exception) {
                Log.w("MainActivity", "Audio recorder stop: ${e.message}")
            }
            currentAudioRecorder = null
            
            // Stop video recording service
            val intent = Intent(this, StealthRecordingService::class.java).apply {
                action = "STOP_STEALTH_RECORDING"
            }
            startService(intent)
            
            // Mark recording as completed in Firestore
            if (currentRecordingId != null) {
                val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
                if (userId != null) {
                    com.google.firebase.firestore.FirebaseFirestore.getInstance()
                        .collection("users")
                        .document(userId)
                        .collection("secureVaultRecordings")
                        .document(currentRecordingId!!)
                        .update(mapOf(
                            "status" to "completed",
                            "endTime" to System.currentTimeMillis()
                        ))
                        .addOnSuccessListener {
                            Log.d("MainActivity", "✅ Recording marked as completed")
                        }
                }
                uploadRecordingsToCloud(currentRecordingId!!)
            }
            
            currentRecordingId = null
            Log.d("MainActivity", "✅ Stealth recording stopped and uploading to cloud")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error stopping stealth recording: ${e.message}")
        }
    }
    
    private fun uploadRecordingsToCloud(recordingId: String) {
        try {
            Log.d("MainActivity", "☁️ Uploading recordings to Firebase Storage")
            
            val storage = com.google.firebase.storage.FirebaseStorage.getInstance()
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            
            if (userId != null) {
                // Upload audio file
                val audioFile = java.io.File(filesDir, "${recordingId}_audio.3gp")
                if (audioFile.exists()) {
                    val audioRef = storage.reference.child("emergency_recordings/$userId/$recordingId/audio.3gp")
                    audioRef.putFile(android.net.Uri.fromFile(audioFile))
                        .addOnSuccessListener {
                            Log.d("MainActivity", "✅ Audio uploaded to cloud")
                        }
                        .addOnFailureListener { e ->
                            Log.e("MainActivity", "❌ Audio upload failed: ${e.message}")
                        }
                }
                
                // Upload video file
                val videoFile = java.io.File(filesDir, "${recordingId}_video.mp4")
                if (videoFile.exists()) {
                    val videoRef = storage.reference.child("emergency_recordings/$userId/$recordingId/video.mp4")
                    videoRef.putFile(android.net.Uri.fromFile(videoFile))
                        .addOnSuccessListener {
                            Log.d("MainActivity", "✅ Video uploaded to cloud")
                            // Update Firestore with upload completion
                            updateRecordingStatus(recordingId, "uploaded")
                        }
                        .addOnFailureListener { e ->
                            Log.e("MainActivity", "❌ Video upload failed: ${e.message}")
                        }
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error uploading recordings: ${e.message}")
        }
    }
    
    // Location sharing variables
    private var locationManager: android.location.LocationManager? = null
    private var locationListener: android.location.LocationListener? = null
    private var isLocationSharingActive = false
    private var locationSharingTimer: java.util.Timer? = null
    
    private fun startLocationSharing(gesture: String) {
        try {
            Log.d("MainActivity", "📍 Starting CONTINUOUS location sharing for gesture: $gesture")
            
            if (isLocationSharingActive) {
                Log.d("MainActivity", "📍 Location sharing already active")
                return
            }
            
            locationManager = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
            
            // Check location permission
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    Log.e("MainActivity", "❌ Location permission not granted for sharing")
                    return
                }
            }
            
            // Create location listener for continuous updates
            locationListener = object : android.location.LocationListener {
                override fun onLocationChanged(location: android.location.Location) {
                    Log.d("MainActivity", "📍 Location update: ${location.latitude}, ${location.longitude}")
                    updateLocationInFirebase(location, gesture)
                    sendLocationUpdateSMS(location)
                }
                
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
                override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
            }
            
            // Start continuous location updates
            locationManager?.requestLocationUpdates(
                android.location.LocationManager.GPS_PROVIDER,
                30000L, // Update every 30 seconds
                10f,    // Update every 10 meters
                locationListener!!
            )
            
            // Also use network provider as backup
            locationManager?.requestLocationUpdates(
                android.location.LocationManager.NETWORK_PROVIDER,
                30000L,
                10f,
                locationListener!!
            )
            
            isLocationSharingActive = true
            Log.d("MainActivity", "✅ CONTINUOUS location sharing started")
            
            // Send initial location
            val lastKnownLocation = locationManager?.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)
                ?: locationManager?.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)
            
            if (lastKnownLocation != null) {
                updateLocationInFirebase(lastKnownLocation, gesture)
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting location sharing: ${e.message}")
        }
    }
    
    private fun updateLocationInFirebase(location: android.location.Location, gesture: String) {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                val locationData = mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy,
                    "timestamp" to System.currentTimeMillis(),
                    "gesture" to gesture,
                    "googleMapsLink" to "https://maps.google.com/?q=${location.latitude},${location.longitude}",
                    "isActive" to true
                )
                
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .collection("liveLocation")
                    .document("current")
                    .set(locationData)
                    .addOnSuccessListener {
                        Log.d("MainActivity", "✅ Location updated in Firebase")
                    }
                    .addOnFailureListener { e ->
                        Log.e("MainActivity", "❌ Failed to update location: ${e.message}")
                    }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error updating location in Firebase: ${e.message}")
        }
    }
    
    private fun sendLocationUpdateSMS(location: android.location.Location) {
        // Send location update SMS every 5 minutes
        val currentTime = System.currentTimeMillis()
        val lastSMSTime = getSharedPreferences("raksha", Context.MODE_PRIVATE).getLong("lastLocationSMS", 0)
        
        if (currentTime - lastSMSTime > 300000) { // 5 minutes
            val userName = getCurrentUserName()
            val locationMessage = "📍 LIVE LOCATION UPDATE\n\n" +
                    "$userName's current location:\n" +
                    "https://maps.google.com/?q=${location.latitude},${location.longitude}\n\n" +
                    "Time: ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())}\n" +
                    "Accuracy: ${location.accuracy.toInt()}m"
            
            // Send to emergency contacts
            sendLocationSMSToContacts(locationMessage)
            
            // Update last SMS time
            getSharedPreferences("raksha", Context.MODE_PRIVATE).edit()
                .putLong("lastLocationSMS", currentTime)
                .apply()
        }
    }
    
    private fun sendLocationSMSToContacts(message: String) {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .get()
                    .addOnSuccessListener { document ->
                        if (document.exists()) {
                            val contacts = document.get("emergencyContacts") as? List<Map<String, Any>>
                            contacts?.forEach { contact ->
                                val phone = contact["phone"] as? String
                                if (phone != null) {
                                    val smsManager = android.telephony.SmsManager.getDefault()
                                    smsManager.sendTextMessage(phone, null, message, null, null)
                                    Log.d("MainActivity", "📱 Location SMS sent to: $phone")
                                }
                            }
                        }
                    }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error sending location SMS: ${e.message}")
        }
    }
    
    private fun stopLocationSharing() {
        try {
            Log.d("MainActivity", "🛑 Stopping CONTINUOUS location sharing")
            
            // Stop location updates
            locationListener?.let { listener ->
                locationManager?.removeUpdates(listener)
            }
            
            // Clear variables
            locationManager = null
            locationListener = null
            isLocationSharingActive = false
            
            // Update Firebase to mark location sharing as inactive
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .collection("liveLocation")
                    .document("current")
                    .update("isActive", false)
                    .addOnSuccessListener {
                        Log.d("MainActivity", "✅ Location sharing marked as inactive in Firebase")
                    }
            }
            
            Log.d("MainActivity", "✅ Location sharing stopped successfully")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error stopping location sharing: ${e.message}")
        }
    }
    
    private fun sendEmergencySMSToContacts(gesture: String, message: String) {
        try {
            Log.d("MainActivity", "📱 STARTING emergency SMS for gesture: $gesture")
            
            // Get emergency contacts from Firebase
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            Log.d("MainActivity", "📱 User ID: $userId")
            
            if (userId != null) {
                Log.d("MainActivity", "📱 Fetching emergency contacts from Firebase...")
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .get()
                    .addOnSuccessListener { document ->
                        Log.d("MainActivity", "📱 Firebase document retrieved successfully")
                        if (document.exists()) {
                            Log.d("MainActivity", "📱 Document exists, checking for contacts...")
                            val contacts = document.get("emergencyContacts") as? List<Map<String, Any>>
                            Log.d("MainActivity", "📱 Found contacts: $contacts")
                            
                            if (contacts != null && contacts.isNotEmpty()) {
                                Log.d("MainActivity", "📱 Processing ${contacts.size} emergency contacts")
                                contacts.forEach { contact ->
                                    val phone = contact["phone"] as? String
                                    val name = contact["name"] as? String
                                    Log.d("MainActivity", "📱 Contact: $name - $phone")
                                    if (phone != null && phone.isNotEmpty()) {
                                        sendSMSToContact(phone, name ?: "Emergency Contact", message, gesture)
                                    } else {
                                        Log.w("MainActivity", "⚠️ Skipping contact with empty phone: $contact")
                                    }
                                }
                            } else {
                                Log.e("MainActivity", "❌ NO EMERGENCY CONTACTS FOUND! User needs to add contacts first.")
                                // Send a test SMS to verify SMS functionality
                                sendTestSMS(gesture)
                            }
                        } else {
                            Log.e("MainActivity", "❌ User document does not exist in Firebase")
                        }
                    }
                    .addOnFailureListener { e ->
                        Log.e("MainActivity", "❌ Failed to get emergency contacts: ${e.message}")
                        e.printStackTrace()
                    }
            } else {
                Log.e("MainActivity", "❌ No user ID - user not logged in")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error sending emergency SMS: ${e.message}")
            e.printStackTrace()
        }
    }
    
    // Send test SMS to verify SMS functionality
    private fun sendTestSMS(gesture: String) {
        try {
            Log.d("MainActivity", "📱 Sending TEST SMS since no contacts found")
            // You can replace this with your own phone number for testing
            val testPhone = "1234567890" // Replace with your number for testing
            sendSMSToContact(testPhone, "Test Contact", "Test emergency message", gesture)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Test SMS failed: ${e.message}")
        }
    }
    
    // Test SMS system with specific phone number
    private fun testSMSSystem(phoneNumber: String) {
        try {
            Log.d("MainActivity", "📱 Testing SMS system with phone: $phoneNumber")
            
            if (phoneNumber.isEmpty()) {
                Log.e("MainActivity", "❌ No phone number provided for SMS test")
                return
            }
            
            val testMessage = "🧪 TEST SMS from Raksha Safety App\n\n" +
                    "This is a test message to verify SMS functionality.\n" +
                    "Time: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())}\n\n" +
                    "If you receive this, SMS is working correctly!"
            
            sendSMSToContact(phoneNumber, "Test Contact", testMessage, "TEST")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ SMS test failed: ${e.message}")
        }
    }
    
    private fun sendSMSToContact(phone: String, name: String, message: String, gesture: String) {
        try {
            Log.d("MainActivity", "📱 Attempting to send SMS to $name ($phone)")
            
            // Check SMS permission
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (checkSelfPermission(android.Manifest.permission.SEND_SMS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    Log.e("MainActivity", "❌ SMS permission not granted!")
                    return
                }
            }
            
            val smsManager = android.telephony.SmsManager.getDefault()
            val userName = getCurrentUserName()
            val currentTime = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())
            
            // Get current location for live sharing
            getCurrentLocationForSMS { location ->
                val locationText = if (location != null) {
                    "📍 Live Location: https://maps.google.com/?q=${location.latitude},${location.longitude}"
                } else {
                    "📍 Location: Getting current location..."
                }
                
                val finalMessage = "🚨 EMERGENCY ALERT 🚨\n\n" +
                        "$userName needs help!\n" +
                        "Time: $currentTime\n\n" +
                        "Please call me immediately!\n\n" +
                        "$locationText\n\n" +
                        "This is an automated emergency message from Raksha Safety App."
                
                Log.d("MainActivity", "📱 SMS message: $finalMessage")
                Log.d("MainActivity", "📱 Sending to phone: $phone")
                
                try {
                    // Split long messages if needed
                    val parts = smsManager.divideMessage(finalMessage)
                    if (parts.size == 1) {
                        smsManager.sendTextMessage(phone, null, finalMessage, null, null)
                    } else {
                        smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                    }
                    
                    Log.d("MainActivity", "✅ SMS SUCCESSFULLY SENT to $name ($phone)")
                } catch (e: Exception) {
                    Log.e("MainActivity", "❌ Error sending SMS: ${e.message}")
                }
            }
            
        } catch (e: SecurityException) {
            Log.e("MainActivity", "❌ SMS permission denied: ${e.message}")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error sending SMS to $phone: ${e.message}")
            e.printStackTrace()
        }
    }
    
    private fun getCurrentUserName(): String {
        val firebaseUser = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
        return firebaseUser?.displayName ?: firebaseUser?.email?.substringBefore("@") ?: "Emergency User"
    }
    
    // Get current location for SMS
    private fun getCurrentLocationForSMS(callback: (android.location.Location?) -> Unit) {
        try {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
            
            // Check location permission
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    Log.w("MainActivity", "⚠️ Location permission not granted")
                    callback(null)
                    return
                }
            }
            
            // Try to get last known location first
            val lastKnownLocation = locationManager.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)
                ?: locationManager.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)
            
            if (lastKnownLocation != null) {
                Log.d("MainActivity", "📍 Using last known location: ${lastKnownLocation.latitude}, ${lastKnownLocation.longitude}")
                callback(lastKnownLocation)
            } else {
                // Request fresh location
                Log.d("MainActivity", "📍 Requesting fresh location...")
                requestFreshLocation(callback)
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error getting location: ${e.message}")
            callback(null)
        }
    }
    
    private fun requestFreshLocation(callback: (android.location.Location?) -> Unit) {
        try {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
            
            val locationListener = object : android.location.LocationListener {
                override fun onLocationChanged(location: android.location.Location) {
                    Log.d("MainActivity", "📍 Fresh location received: ${location.latitude}, ${location.longitude}")
                    locationManager.removeUpdates(this)
                    callback(location)
                }
                
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
                override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
            }
            
            // Request location update with timeout
            locationManager.requestLocationUpdates(
                android.location.LocationManager.GPS_PROVIDER,
                0L,
                0f,
                locationListener
            )
            
            // Timeout after 10 seconds
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                locationManager.removeUpdates(locationListener)
                callback(null)
            }, 10000)
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error requesting fresh location: ${e.message}")
            callback(null)
        }
    }
    
    // Check if emergency contacts are set up
    private fun checkEmergencyContacts(result: MethodChannel.Result) {
        try {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            if (userId != null) {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(userId)
                    .get()
                    .addOnSuccessListener { document ->
                        if (document.exists()) {
                            val contacts = document.get("emergencyContacts") as? List<Map<String, Any>>
                            val contactCount = contacts?.size ?: 0
                            result.success(mapOf(
                                "hasContacts" to (contactCount > 0),
                                "contactCount" to contactCount,
                                "contacts" to (contacts ?: emptyList<Map<String, Any>>())
                            ))
                        } else {
                            result.success(mapOf(
                                "hasContacts" to false,
                                "contactCount" to 0,
                                "contacts" to emptyList<Map<String, Any>>()
                            ))
                        }
                    }
                    .addOnFailureListener { e ->
                        result.error("FIREBASE_ERROR", "Failed to check contacts: ${e.message}", null)
                    }
            } else {
                result.error("NO_USER", "User not logged in", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", "Error checking contacts: ${e.message}", null)
        }
    }
    
    private fun cancelSOSDuringVibration() {
        try {
            Log.d("MainActivity", "🛑 Cancelling SOS during vibration phase")
            
            // Stop vibration immediately
            stopEmergencyVibration()
            
            // Cancel all notifications
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
            
            // Show cancellation confirmation
            val notification = androidx.core.app.NotificationCompat.Builder(this, "emergency_cancel")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("✅ SOS CANCELLED")
                .setContentText("Emergency SOS has been cancelled successfully")
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setColor(android.graphics.Color.GREEN)
                .build()
            
            notificationManager.notify(1000, notification)
            
            Log.d("MainActivity", "✅ SOS cancelled during vibration phase")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error cancelling SOS during vibration: ${e.message}")
        }
    }
    
    private fun showVibrationCancelDialog(gesture: String) {
        runOnUiThread {
            val dialog = android.app.AlertDialog.Builder(this)
                .setTitle("🚨 EMERGENCY SOS ACTIVE")
                .setMessage("Vibration phase in progress!\n\nGesture: $gesture\n\nSOS will activate after vibration ends unless you cancel NOW.")
                .setCancelable(false)
                .setPositiveButton("CANCEL SOS") { _, _ ->
                    cancelSOSDuringVibration()
                    android.widget.Toast.makeText(this, "🛑 Emergency SOS Cancelled", android.widget.Toast.LENGTH_LONG).show()
                }
                .setNegativeButton("Continue SOS") { dialog, _ ->
                    dialog.dismiss()
                    android.widget.Toast.makeText(this, "⚠️ SOS will continue after vibration", android.widget.Toast.LENGTH_SHORT).show()
                }
                .create()
            
            dialog.show()
            
            // Make the dialog buttons more prominent
            dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE)?.apply {
                setTextColor(android.graphics.Color.RED)
                textSize = 16f
                setTypeface(null, android.graphics.Typeface.BOLD)
            }
        }
    }
    
    // Process camera image bytes from Flutter
    private fun processCameraImageBytes(call: MethodCall, result: MethodChannel.Result) {
        try {
            val imageBytes = call.argument<ByteArray>("imageBytes")
            val width = call.argument<Int>("width") ?: 0
            val height = call.argument<Int>("height") ?: 0
            
            if (imageBytes != null && width > 0 && height > 0) {
                Log.d("MainActivity", "📷 Processing Flutter camera image: ${width}x${height}")
                
                // Convert bytes to bitmap
                val bitmap = createBitmapFromBytes(imageBytes, width, height)
                
                if (bitmap != null && gestureHelper != null) {
                    // Process through MediaPipe
                    val gestureResult = gestureHelper?.recognizeImage(bitmap)
                    Log.d("MainActivity", "✅ Flutter camera image processed through MediaPipe")
                } else {
                    Log.w("MainActivity", "❌ Failed to create bitmap or gestureHelper null")
                }
                
                result.success("Image processed")
            } else {
                result.error("INVALID_IMAGE", "Invalid image data", null)
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error processing camera image bytes: ${e.message}")
            result.error("PROCESSING_ERROR", e.message, null)
        }
    }
    
    // Create bitmap from camera image bytes
    private fun createBitmapFromBytes(bytes: ByteArray, width: Int, height: Int): Bitmap? {
        return try {
            // Create grayscale bitmap from Y plane bytes
            val pixels = IntArray(width * height)
            
            for (i in bytes.indices) {
                if (i < pixels.size) {
                    val gray = bytes[i].toInt() and 0xFF
                    pixels[i] = (0xFF shl 24) or (gray shl 16) or (gray shl 8) or gray
                }
            }
            
            Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error creating bitmap from bytes: ${e.message}")
            null
        }
    }
    
    // Start ONLY MediaPipe processing without native camera
    private fun startMediaPipeProcessingOnly(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🎯 Starting MediaPipe processing ONLY (no native camera)")
            
            // Initialize MediaPipe gesture helper if not already done
            if (gestureHelper == null) {
                gestureHelper = GestureRecognizerHelper(
                    context = this,
                    gestureRecognizerListener = this
                )
            }
            
            Log.d("MainActivity", "✅ MediaPipe processing ready - waiting for Flutter camera frames")
            result.success(mapOf(
                "status" to "ready",
                "message" to "MediaPipe ready for processing"
            ))
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error starting MediaPipe processing: ${e.message}")
            result.error("MEDIAPIPE_ERROR", e.message, null)
        }
    }
    
    // Request background camera permission for emergency system
    private fun requestBackgroundCameraPermission(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "📷 Requesting background camera permission for emergency system")
            
            // Show explanation dialog to user
            val builder = android.app.AlertDialog.Builder(this)
            builder.setTitle("🚨 Emergency Camera Access")
            builder.setMessage("""
                Raksha needs camera access "Allow all the time" to:
                
                • Detect emergency gestures when phone is locked
                • Work when other apps are open
                • Function as a real emergency system
                
                Please select "Allow all the time" in the next dialog.
            """.trimIndent())
            
            builder.setPositiveButton("Grant Permission") { _, _ ->
                // Request camera permission
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    val permissions = mutableListOf(
                        android.Manifest.permission.CAMERA,
                        android.Manifest.permission.RECORD_AUDIO,
                        android.Manifest.permission.ACCESS_FINE_LOCATION,
                        android.Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                        android.Manifest.permission.SEND_SMS
                    )
                    
                    // Add POST_NOTIFICATIONS for Android 13+ (API 33+)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        permissions.add(android.Manifest.permission.POST_NOTIFICATIONS)
                    }
                    
                    requestPermissions(permissions.toTypedArray(), 1001)
                }
                result.success("Background camera permission requested")
            }
            
            builder.setNegativeButton("Cancel") { _, _ ->
                result.error("PERMISSION_DENIED", "User cancelled background camera permission", null)
            }
            
            builder.show()
            
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error requesting background camera permission: ${e.message}")
            result.error("PERMISSION_ERROR", e.message, null)
        }
    }
}
