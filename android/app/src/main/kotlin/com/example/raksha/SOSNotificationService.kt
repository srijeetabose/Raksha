package com.example.raksha

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SOSNotificationService : Service() {

    private val TAG = "SOSNotificationService"
    private val NOTIFICATION_ID = 9999
    private val CHANNEL_ID = "sos_countdown_channel"

    private var secondsRemaining = 10
    private var isCancelled = false
    private var triggerWord = "Unknown"

    private val handler = Handler(Looper.getMainLooper())
    private var countdownRunnable: Runnable? = null

    // Contacts cached after first Firestore fetch — used for repeating location SMS
    private var cachedContacts: List<Map<String, String>> = emptyList()
    private var locationTimer: java.util.Timer? = null

    // ── Broadcast receivers ───────────────────────────────────────────────────

    private val cancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.raksha.CANCEL_SOS") {
                Log.d(TAG, "Received cancel broadcast")
                cancelSOS()
            }
        }
    }

    /** Logs the actual SMS send result so we can see failures in logcat. */
    private val smsSentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val phone = intent?.getStringExtra("phone") ?: "unknown"
            when (resultCode) {
                android.app.Activity.RESULT_OK ->
                    Log.d(TAG, "✅ SMS sent OK to $phone")
                SmsManager.RESULT_ERROR_GENERIC_FAILURE ->
                    Log.e(TAG, "❌ SMS FAILED (generic error) to $phone")
                SmsManager.RESULT_ERROR_NO_SERVICE ->
                    Log.e(TAG, "❌ SMS FAILED (no service) to $phone")
                SmsManager.RESULT_ERROR_NULL_PDU ->
                    Log.e(TAG, "❌ SMS FAILED (null PDU) to $phone")
                SmsManager.RESULT_ERROR_RADIO_OFF ->
                    Log.e(TAG, "❌ SMS FAILED (radio off / airplane mode) to $phone")
                else ->
                    Log.e(TAG, "❌ SMS FAILED (resultCode=$resultCode) to $phone")
            }
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val cancelFilter = IntentFilter("com.example.raksha.CANCEL_SOS")
        val smsFilter = IntentFilter("com.example.raksha.SMS_SENT")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(cancelReceiver, cancelFilter, RECEIVER_NOT_EXPORTED)
            registerReceiver(smsSentReceiver, smsFilter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(cancelReceiver, cancelFilter)
            registerReceiver(smsSentReceiver, smsFilter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            triggerWord = intent?.getStringExtra("TRIGGER_WORD") ?: "Unknown"
            startForeground(NOTIFICATION_ID, buildNotification(10))
            startSecureVaultRecording()
            startCountdown()
        } catch (e: Exception) {
            Log.e(TAG, "Error starting: ${e.message}")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        countdownRunnable?.let { handler.removeCallbacks(it) }
        locationTimer?.cancel()
        try { unregisterReceiver(cancelReceiver) } catch (e: Exception) { }
        try { unregisterReceiver(smsSentReceiver) } catch (e: Exception) { }
    }

    // ── Recording ─────────────────────────────────────────────────────────────

    private fun startSecureVaultRecording() {
        try {
            val recordingId = "SOS_${System.currentTimeMillis()}"
            File(filesDir, ".secure_vault").mkdirs()
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
            FirebaseFirestore.getInstance()
                .collection("users").document(userId)
                .collection("secureVaultRecordings").document(recordingId)
                .set(hashMapOf(
                    "id" to recordingId,
                    "gesture" to triggerWord,
                    "startTime" to System.currentTimeMillis(),
                    "hasAudio" to true,
                    "hasVideo" to true,
                    "status" to "recording"
                ))
        } catch (e: Exception) {
            Log.e(TAG, "Error saving metadata: ${e.message}")
        }
    }

    // ── Notification ──────────────────────────────────────────────────────────

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
        val cancelPendingIntent = PendingIntent.getBroadcast(
            this, 0, Intent("com.example.raksha.CANCEL_SOS"),
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

    // ── Countdown ─────────────────────────────────────────────────────────────

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

        // Send initial SOS SMS from the service — reliable even if activity is blocked on Android 12+
        sendSOSMessages()

        // Try to show the visual countdown activity
        try {
            startActivity(Intent(this, SOSCountdownActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("TRIGGER_WORD", triggerWord)
                putExtra("SKIP_TO_VIBRATION", true)
            })
            sendFullScreenNotification()
        } catch (e: Exception) {
            Log.e(TAG, "Activity launch blocked: ${e.message}")
        }

        handler.postDelayed({ stopServiceAndCleanup() }, 10000)
    }

    private fun sendFullScreenNotification() {
        try {
            val fullScreenPendingIntent = PendingIntent.getActivity(
                this, 0,
                Intent(this, SOSCountdownActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("TRIGGER_WORD", triggerWord)
                    putExtra("SKIP_TO_VIBRATION", true)
                },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            getSystemService(NotificationManager::class.java)?.notify(
                NOTIFICATION_ID + 1,
                NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle("EMERGENCY - 7 SECOND VIBRATION")
                    .setContentText("Tap to cancel")
                    .setSmallIcon(android.R.drawable.ic_dialog_alert)
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_ALARM)
                    .setFullScreenIntent(fullScreenPendingIntent, true)
                    .setAutoCancel(false)
                    .build()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error sending full-screen notification: ${e.message}")
        }
    }

    private fun stopServiceAndCleanup() {
        locationTimer?.cancel()
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

    // ── SMS sending ───────────────────────────────────────────────────────────

    private fun getSmsManager(): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

    private fun getCurrentLocationText(): String {
        return try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)
            if (loc != null)
                "\uD83D\uDCCD Live Location: https://maps.google.com/?q=${loc.latitude},${loc.longitude}"
            else
                "\uD83D\uDCCD Location: unavailable"
        } catch (e: Exception) {
            Log.e(TAG, "Could not get location: ${e.message}")
            "\uD83D\uDCCD Location: unavailable"
        }
    }

    private fun dispatchSMS(phone: String, message: String) {
        try {
            val sentPI = PendingIntent.getBroadcast(
                this, phone.hashCode(),
                Intent("com.example.raksha.SMS_SENT").putExtra("phone", phone),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val sms = getSmsManager()
            val parts = sms.divideMessage(message)
            if (parts.size == 1) {
                sms.sendTextMessage(phone, null, message, sentPI, null)
            } else {
                val sentPIs = ArrayList<PendingIntent>(parts.size).apply { repeat(parts.size) { add(sentPI) } }
                sms.sendMultipartTextMessage(phone, null, parts, sentPIs, null)
            }
            Log.d(TAG, "SMS dispatched to $phone")
        } catch (e: Exception) {
            Log.e(TAG, "SMS dispatch failed to $phone: ${e.message}")
        }
    }

    /**
     * Fetches emergency contacts from Firestore, sends the initial SOS SMS,
     * then starts the 2-minute repeating location update loop.
     */
    private fun sendSOSMessages() {
        try {
            val userId = FirebaseAuth.getInstance().currentUser?.uid ?: run {
                Log.e(TAG, "No user logged in — cannot send SOS")
                return
            }

            val locationText = getCurrentLocationText()

            FirebaseFirestore.getInstance().collection("users").document(userId).get()
                .addOnSuccessListener { document ->
                    if (!document.exists()) {
                        Log.e(TAG, "User document not found")
                        return@addOnSuccessListener
                    }

                    val rawContacts = document.get("emergencyContacts") as? List<*>
                    val contacts = rawContacts?.mapNotNull { item ->
                        (item as? Map<*, *>)?.let { map ->
                            mapOf(
                                "name" to (map["name"] as? String ?: ""),
                                "phone" to (map["phone"] as? String ?: "")
                            )
                        }
                    } ?: emptyList()

                    if (contacts.isEmpty()) {
                        Log.e(TAG, "No emergency contacts configured")
                        handler.post {
                            android.widget.Toast.makeText(
                                this, "❌ No emergency contacts set up!", android.widget.Toast.LENGTH_LONG
                            ).show()
                        }
                        return@addOnSuccessListener
                    }

                    // Cache contacts for the repeating location loop
                    cachedContacts = contacts

                    val userName = document.getString("name")
                        ?: document.getString("displayName") ?: "User"
                    val currentTime = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())

                    val message = "\uD83D\uDEA8 EMERGENCY ALERT \uD83D\uDEA8\n\n" +
                        "$userName needs help!\n" +
                        "Time: $currentTime\n\n" +
                        "Please call me immediately!\n\n" +
                        "$locationText\n\n" +
                        "This is an automated emergency message from Raksha Safety App."

                    var sentCount = 0
                    for (contact in contacts) {
                        val phone = contact["phone"] ?: continue
                        if (phone.isNotEmpty()) {
                            dispatchSMS(phone, message)
                            sentCount++
                        }
                    }

                    Log.d(TAG, "Initial SOS SMS dispatched to $sentCount contact(s)")
                    handler.post {
                        android.widget.Toast.makeText(
                            this, "🚨 SOS sent to $sentCount contact(s)", android.widget.Toast.LENGTH_LONG
                        ).show()
                    }

                    // Start repeating location updates every 2 minutes
                    startRepeatingLocationSMS()
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Firestore fetch failed: ${e.message}")
                }
        } catch (e: Exception) {
            Log.e(TAG, "Error in sendSOSMessages: ${e.message}")
        }
    }

    /** Sends a fresh location update SMS to all cached contacts every 2 minutes. */
    private fun startRepeatingLocationSMS() {
        locationTimer?.cancel()
        locationTimer = java.util.Timer()
        locationTimer?.scheduleAtFixedRate(object : java.util.TimerTask() {
            override fun run() {
                if (isCancelled) { cancel(); return }
                sendLocationUpdateSMS()
            }
        }, 120_000L, 120_000L) // first update after 2 min, then every 2 min
        Log.d(TAG, "✅ Repeating location SMS started (every 2 min)")
    }

    private fun sendLocationUpdateSMS() {
        if (cachedContacts.isEmpty()) return
        val locationText = getCurrentLocationText()
        val updateMsg = "\uD83D\uDEA8 LIVE LOCATION UPDATE \uD83D\uDEA8\n\n" +
            "I still need help!\n\n" +
            "$locationText\n\n" +
            "- Raksha Safety App"

        for (contact in cachedContacts) {
            val phone = contact["phone"] ?: continue
            if (phone.isNotEmpty()) {
                try {
                    getSmsManager().sendTextMessage(phone, null, updateMsg, null, null)
                    Log.d(TAG, "✅ Location update SMS sent to $phone")
                } catch (e: Exception) {
                    Log.e(TAG, "Location update SMS failed to $phone: ${e.message}")
                }
            }
        }
    }

    // ── Cancel ────────────────────────────────────────────────────────────────

    private fun cancelSOS() {
        isCancelled = true
        countdownRunnable?.let { handler.removeCallbacks(it) }
        handler.removeCallbacksAndMessages(null)
        locationTimer?.cancel()
        cachedContacts = emptyList()
        sendBroadcast(Intent("com.example.raksha.CANCEL_SOS_ACTIVITY"))
        try {
            startService(Intent(this, StealthRecordingService::class.java).apply {
                action = "STOP_STEALTH_RECORDING"
            })
        } catch (e: Exception) { }
        handler.post {
            android.widget.Toast.makeText(this, "SOS Cancelled", android.widget.Toast.LENGTH_SHORT).show()
        }
        stopServiceAndCleanup()
    }
}
