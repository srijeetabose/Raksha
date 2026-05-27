package com.example.raksha

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import java.io.File

class SOSNotificationService : Service() {

    private val TAG = "SOSNotificationService"
    private val NOTIFICATION_ID = 9999
    private val CHANNEL_ID = "sos_countdown_channel"

    private var secondsRemaining = 10
    private var isCancelled = false
    private var triggerWord = "Unknown"

    private val handler = Handler(Looper.getMainLooper())
    private var countdownRunnable: Runnable? = null

    private val cancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.raksha.CANCEL_SOS") {
                Log.d(TAG, "Received cancel broadcast")
                cancelSOS()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(cancelReceiver, IntentFilter("com.example.raksha.CANCEL_SOS"), RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(cancelReceiver, IntentFilter("com.example.raksha.CANCEL_SOS"))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            triggerWord = intent?.getStringExtra("TRIGGER_WORD") ?: "Unknown"
            val notification = buildNotification(10)
            startForeground(NOTIFICATION_ID, notification)
            startSecureVaultRecording()
            startCountdown()
        } catch (e: Exception) {
            Log.e(TAG, "Error starting: ${e.message}")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startSecureVaultRecording() {
        try {
            val recordingId = "SOS_${System.currentTimeMillis()}"
            val secureVaultDir = File(filesDir, ".secure_vault")
            if (!secureVaultDir.exists()) secureVaultDir.mkdirs()

            val recordingIntent = Intent(this, StealthRecordingService::class.java).apply {
                action = "START_STEALTH_RECORDING"
                putExtra("recordingId", recordingId)
                putExtra("gesture", triggerWord)
                putExtra("timestamp", System.currentTimeMillis())
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(recordingIntent)
            } else {
                startService(recordingIntent)
            }

            saveRecordingMetadataToFirebase(recordingId)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting recording: ${e.message}")
        }
    }

    private fun saveRecordingMetadataToFirebase(recordingId: String) {
        try {
            val userId = FirebaseAuth.getInstance().currentUser?.uid ?: return
            val data = hashMapOf(
                "id" to recordingId,
                "gesture" to triggerWord,
                "startTime" to System.currentTimeMillis(),
                "hasAudio" to true,
                "hasVideo" to true,
                "status" to "recording"
            )
            FirebaseFirestore.getInstance()
                .collection("users").document(userId)
                .collection("secureVaultRecordings").document(recordingId)
                .set(data)
        } catch (e: Exception) {
            Log.e(TAG, "Error saving metadata: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "SOS Countdown", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(seconds: Int): Notification {
        val cancelIntent = Intent("com.example.raksha.CANCEL_SOS")
        val cancelPendingIntent = PendingIntent.getBroadcast(
            this, 0, cancelIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SOS ACTIVATED - Tap CANCEL to stop")
            .setContentText("Trigger: $triggerWord | $seconds seconds remaining")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_delete, "CANCEL SOS", cancelPendingIntent)
            .build()
    }

    private fun startCountdown() {
        countdownRunnable = object : Runnable {
            override fun run() {
                if (isCancelled) { stopSelf(); return }
                secondsRemaining--
                getSystemService(NotificationManager::class.java)
                    ?.notify(NOTIFICATION_ID, buildNotification(secondsRemaining))
                if (secondsRemaining > 0) {
                    handler.postDelayed(this, 1000)
                } else {
                    launchVibrationPopup()
                }
            }
        }
        handler.postDelayed(countdownRunnable!!, 1000)
    }

    private fun launchVibrationPopup() {
        if (isCancelled) { stopServiceAndCleanup(); return }
        // Send SMS directly — don't rely on activity launch (blocked by Android 12+)
        sendSOSMessages()
        try {
            val activityIntent = Intent(this, SOSCountdownActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("TRIGGER_WORD", triggerWord)
                putExtra("SKIP_TO_VIBRATION", true)
            }
            startActivity(activityIntent)
            sendFullScreenNotification()
        } catch (e: Exception) {
            Log.e(TAG, "Activity launch blocked: ${e.message}")
        }
        handler.postDelayed({ stopServiceAndCleanup() }, 10000)
    }

    private fun sendFullScreenNotification() {
        try {
            val fullScreenIntent = Intent(this, SOSCountdownActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("TRIGGER_WORD", triggerWord)
                putExtra("SKIP_TO_VIBRATION", true)
            }
            val fullScreenPendingIntent = PendingIntent.getActivity(
                this, 0, fullScreenIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("EMERGENCY - 7 SECOND VIBRATION")
                .setContentText("Tap to cancel")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setAutoCancel(false)
                .build()
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID + 1, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error sending full-screen notification: ${e.message}")
        }
    }

    private fun stopServiceAndCleanup() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        } catch (e: Exception) { }
    }

    private fun sendSOSMessages() {
        try {
            val userId = FirebaseAuth.getInstance().currentUser?.uid ?: return
            FirebaseFirestore.getInstance().collection("users").document(userId).get()
                .addOnSuccessListener { document ->
                    if (!document.exists()) return@addOnSuccessListener
                    val rawContacts = document.get("emergencyContacts") as? List<*> ?: return@addOnSuccessListener
                    val contacts = rawContacts.mapNotNull { item ->
                        (item as? Map<*, *>)?.let { map ->
                            mapOf("name" to (map["name"] as? String ?: ""), "phone" to (map["phone"] as? String ?: ""))
                        }
                    }
                    if (contacts.isEmpty()) {
                        Log.e(TAG, "No emergency contacts")
                        return@addOnSuccessListener
                    }
                    val location = document.getString("lastKnownLocation") ?: "Location unavailable"
                    val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        getSystemService(SmsManager::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }
                    val message = "EMERGENCY! I need help! Location: $location - Raksha Safety App"
                    var sentCount = 0
                    for (contact in contacts) {
                        val phone = contact["phone"] ?: continue
                        if (phone.isNotEmpty()) {
                            try {
                                smsManager.sendTextMessage(phone, null, message, null, null)
                                sentCount++
                                Log.d(TAG, "SMS sent to $phone")
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to send SMS: ${e.message}")
                            }
                        }
                    }
                    Log.d(TAG, "Total SMS sent: $sentCount")
                    android.widget.Toast.makeText(this, "SMS sent to $sentCount contact(s)", android.widget.Toast.LENGTH_LONG).show()
                }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending SOS: ${e.message}")
        }
    }

    private fun cancelSOS() {
        isCancelled = true
        countdownRunnable?.let { handler.removeCallbacks(it) }
        handler.removeCallbacksAndMessages(null)
        sendBroadcast(Intent("com.example.raksha.CANCEL_SOS_ACTIVITY"))
        try {
            val stopRecording = Intent(this, StealthRecordingService::class.java).apply {
                action = "STOP_STEALTH_RECORDING"
            }
            startService(stopRecording)
        } catch (e: Exception) { }
        android.widget.Toast.makeText(this, "SOS Cancelled", android.widget.Toast.LENGTH_SHORT).show()
        stopServiceAndCleanup()
    }

    override fun onDestroy() {
        super.onDestroy()
        countdownRunnable?.let { handler.removeCallbacks(it) }
        try { unregisterReceiver(cancelReceiver) } catch (e: Exception) { }
    }
}
