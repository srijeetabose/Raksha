package com.example.raksha

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.os.Vibrator
import android.os.VibrationEffect
import android.telephony.SmsManager
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore

class SOSCountdownActivity : AppCompatActivity() {
    
    private var countDownTimer: CountDownTimer? = null
    private var secondsRemaining = 10
    private var isCancelled = false
    private var wakeLock: android.os.PowerManager.WakeLock? = null
    // True when launched by SOSNotificationService (which already sent SMS)
    private var smsSentByService = false
    
    // Handler and Runnable for vibration countdown
    private val vibrationHandler = Handler(Looper.getMainLooper())
    private var vibrationRunnable: Runnable? = null
    
    // UI elements
    private lateinit var layout: android.widget.LinearLayout
    private lateinit var titleText: TextView
    private lateinit var triggerText: TextView
    private lateinit var messageText: TextView
    private lateinit var countdownText: TextView
    private lateinit var cancelButton: Button
    
    private val TAG = "SOSCountdownActivity"
    
    // Broadcast receiver for cancel events
    private val cancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.raksha.CANCEL_SOS" ||
                intent?.action == "com.example.raksha.CANCEL_SOS_ACTIVITY") {
                Log.d(TAG, "Received cancel broadcast")
                cancelSOS()
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        Log.d(TAG, "🚀 SOSCountdownActivity started from background")
        
        // CRITICAL: Acquire wake lock to keep screen on and prevent activity from being killed
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            wakeLock = powerManager.newWakeLock(
                android.os.PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP or
                android.os.PowerManager.ON_AFTER_RELEASE,
                "Raksha::SOSWakeLock"
            )
            wakeLock?.acquire(20000) // 20 seconds max
            Log.d(TAG, "✅ Wake lock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring wake lock: ${e.message}")
        }
        
        // CRITICAL: Show as full-screen overlay over ALL apps - MUST be set BEFORE setContentView
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        
        // Make it appear over other apps
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv() // Make it touchable
        )
        
        // Set window type to show over other apps - CRITICAL for background launch
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                window.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
            } else {
                @Suppress("DEPRECATION")
                window.setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT)
            }
            Log.d(TAG, "✅ Window type set for overlay")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting window type: ${e.message}")
        }
        
        // Dismiss keyguard
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                keyguardManager.requestDismissKeyguard(this, null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error dismissing keyguard: ${e.message}")
        }
        
        // Cancel only via on-screen button — no broadcast receiver needed
        // (prevents accidental cancellation from stale broadcasts)
        
        setupUI()
        
        // Check if we should skip to vibration phase
        val skipToVibration = intent.getBooleanExtra("SKIP_TO_VIBRATION", false)
        if (skipToVibration) {
            smsSentByService = true // Service already sent SMS — don't send again
            Log.d(TAG, "⏩ Skipping to vibration phase (from background, SMS already sent)")
            showVibrationPhase()
        } else {
            startCountdown()
        }
    }
    
    private fun setupUI() {
        // Create layout
        layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setBackgroundColor(android.graphics.Color.RED)
            setPadding(50, 100, 50, 100)
            gravity = android.view.Gravity.CENTER
        }
        
        titleText = TextView(this).apply {
            text = "🚨 EMERGENCY SOS"
            textSize = 32f
            setTextColor(android.graphics.Color.WHITE)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, 40)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        
        triggerText = TextView(this).apply {
            val trigger = intent.getStringExtra("TRIGGER_WORD") ?: "Voice"
            text = "Trigger: \"$trigger\""
            textSize = 24f
            setTextColor(android.graphics.Color.WHITE)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, 40)
        }
        
        messageText = TextView(this).apply {
            text = "SOS will activate in:"
            textSize = 20f
            setTextColor(android.graphics.Color.WHITE)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, 20)
        }
        
        countdownText = TextView(this).apply {
            text = "10"
            textSize = 120f
            setTextColor(android.graphics.Color.WHITE)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 40, 0, 40)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        
        cancelButton = Button(this).apply {
            text = "CANCEL SOS"
            textSize = 24f
            setBackgroundColor(android.graphics.Color.WHITE)
            setTextColor(android.graphics.Color.RED)
            setPadding(60, 40, 60, 40)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setOnClickListener {
                cancelSOS()
            }
        }
        
        layout.addView(titleText)
        layout.addView(triggerText)
        layout.addView(messageText)
        layout.addView(countdownText)
        layout.addView(cancelButton)
        
        setContentView(layout)
    }
    
    private fun startCountdown() {
        Log.d(TAG, "⏰ Starting 10-second countdown")
        
        countDownTimer = object : CountDownTimer(10000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                if (isCancelled) {
                    Log.d(TAG, "🛑 Countdown cancelled by user")
                    cancel()
                    return
                }
                
                secondsRemaining = (millisUntilFinished / 1000).toInt() + 1
                countdownText.text = secondsRemaining.toString()
                Log.d(TAG, "⏰ Countdown: $secondsRemaining")
            }
            
            override fun onFinish() {
                if (!isCancelled) {
                    Log.d(TAG, "⏰ 10-second countdown finished - starting 7-second vibration phase")
                    countdownText.text = "0"
                    showVibrationPhase()
                }
            }
        }.start()
    }
    
    private fun sendSOSAndClose() {
        if (isCancelled) {
            Log.d(TAG, "🛑 SMS sending cancelled")
            return
        }
        
        Log.d(TAG, "📱 Sending SOS SMS")
        
        // Stop vibration
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping vibration: ${e.message}")
        }
        
        // Update UI
        layout.setBackgroundColor(android.graphics.Color.parseColor("#4CAF50")) // Green
        titleText.text = "✅ SOS ACTIVATED"
        countdownText.text = "✓"
        triggerText.text = "Help is on the way!"
        cancelButton.visibility = android.view.View.GONE

        if (smsSentByService) {
            // Service already sent SMS — just show confirmation and close
            messageText.text = "✅ Emergency alert sent!"
            Log.d(TAG, "✅ SMS already sent by service — skipping duplicate send")
            Handler(Looper.getMainLooper()).postDelayed({ finish() }, 3000)
        } else {
            // Manual trigger path — activity is responsible for sending SMS
            messageText.text = "Sending emergency SMS..."
            sendSOSMessages()
        }
    }
    
    private fun sendSOSMessages() {
        Log.d(TAG, "📱 ========== SENDING SOS MESSAGES FROM ACTIVITY ==========")
        
        try {
            val userId = FirebaseAuth.getInstance().currentUser?.uid
            Log.d(TAG, "User ID: $userId")
            
            if (userId == null) {
                Log.e(TAG, "❌ No user logged in")
                messageText.text = "Error: Not logged in"
                android.widget.Toast.makeText(this, "❌ Error: Not logged in", android.widget.Toast.LENGTH_LONG).show()
                
                // Close after 3 seconds even if error
                Handler(Looper.getMainLooper()).postDelayed({
                    finish()
                }, 3000)
                return
            }
            
            Log.d(TAG, "Fetching emergency contacts from Firestore...")
            
            FirebaseFirestore.getInstance()
                .collection("users")
                .document(userId)
                .get()
                .addOnSuccessListener { document ->
                    Log.d(TAG, "✅ Firestore document fetched successfully")
                    
                    if (document.exists()) {
                        Log.d(TAG, "✅ Document exists, reading contacts...")
                        
                        // Safe cast — Firestore returns List<*> at runtime due to type erasure,
                        // so we must map manually instead of casting to List<Map<String, Any>>
                        val rawList = document.get("emergencyContacts") as? List<*>
                        val contacts = rawList?.mapNotNull { item ->
                            (item as? Map<*, *>)?.let { map ->
                                mapOf(
                                    "name" to (map["name"] as? String ?: ""),
                                    "phone" to (map["phone"] as? String ?: "")
                                )
                            }
                        }

                        // Get live GPS location directly from device
                        var locationText = "📍 Location: Getting current location..."
                        try {
                            val lm = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
                            val loc = lm.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)
                                ?: lm.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)
                                ?: lm.getLastKnownLocation(android.location.LocationManager.PASSIVE_PROVIDER)
                            if (loc != null) {
                                locationText = "📍 Live Location: https://maps.google.com/?q=${loc.latitude},${loc.longitude}"
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Could not get location: ${e.message}")
                        }
                        val userName = document.getString("name") ?: document.getString("displayName") ?: "User"
                        val currentTime = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())

                        Log.d(TAG, "📋 Contacts found: ${contacts?.size ?: 0}")
                        Log.d(TAG, "📍 Location: $locationText")
                        
                        if (contacts == null || contacts.isEmpty()) {
                            Log.e(TAG, "❌ NO EMERGENCY CONTACTS CONFIGURED!")
                            messageText.text = "❌ No emergency contacts"
                            android.widget.Toast.makeText(this, "❌ No emergency contacts configured!", android.widget.Toast.LENGTH_LONG).show()
                            Handler(Looper.getMainLooper()).postDelayed({ finish() }, 5000)
                            return@addOnSuccessListener
                        }
                        
                        val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            getSystemService(SmsManager::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            SmsManager.getDefault()
                        }
                        
                        val message = "🚨 EMERGENCY ALERT 🚨\n\n" +
                            "$userName needs help!\n" +
                            "Time: $currentTime\n\n" +
                            "Please call me immediately!\n\n" +
                            "$locationText\n\n" +
                            "This is an automated emergency message from Raksha Safety App."
                        Log.d(TAG, "📨 SMS Message: $message")
                        
                        var sentCount = 0
                        
                        for (contact in contacts) {
                            val phone = contact["phone"]
                            val name = contact["name"]?.takeIf { it.isNotEmpty() } ?: "Unknown"
                            
                            Log.d(TAG, "📞 Processing contact: $name - $phone")
                            
                            if (!phone.isNullOrEmpty()) {
                                try {
                                    val parts = smsManager.divideMessage(message)
                                    if (parts.size == 1) {
                                        smsManager.sendTextMessage(phone, null, message, null, null)
                                    } else {
                                        smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                                    }
                                    sentCount++
                                    Log.d(TAG, "✅ SMS sent successfully to: $name ($phone)")
                                } catch (e: Exception) {
                                    Log.e(TAG, "❌ Failed to send SMS to $name ($phone): ${e.message}")
                                    e.printStackTrace()
                                }
                            } else {
                                Log.e(TAG, "❌ Invalid phone number for contact: $name")
                            }
                        }
                        
                        messageText.text = "✅ SMS sent to $sentCount contact(s)!"
                        Log.d(TAG, "✅ ========== TOTAL SMS SENT: $sentCount ==========")
                        
                        android.widget.Toast.makeText(this, "✅ SMS sent to $sentCount contact(s)", android.widget.Toast.LENGTH_LONG).show()
                        
                        // Start repeating location SMS every 60 seconds
                        startRepeatingLocationSMS(contacts, smsManager)
                        
                        // Close activity after 3 seconds
                        Handler(Looper.getMainLooper()).postDelayed({
                            finish()
                        }, 3000)
                    } else {
                        Log.e(TAG, "❌ User document not found")
                        messageText.text = "Error: User data not found"
                        android.widget.Toast.makeText(this, "❌ User data not found", android.widget.Toast.LENGTH_LONG).show()
                        
                        // Close after 3 seconds
                        Handler(Looper.getMainLooper()).postDelayed({
                            finish()
                        }, 3000)
                    }
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "❌ Failed to fetch contacts: ${e.message}")
                    e.printStackTrace()
                    messageText.text = "Error: ${e.message}"
                    android.widget.Toast.makeText(this, "❌ Failed to fetch contacts: ${e.message}", android.widget.Toast.LENGTH_LONG).show()
                    
                    // Close after 3 seconds even if error
                    Handler(Looper.getMainLooper()).postDelayed({
                        finish()
                    }, 3000)
                }
                
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error sending SOS: ${e.message}")
            e.printStackTrace()
            messageText.text = "Error: ${e.message}"
            android.widget.Toast.makeText(this, "❌ Error: ${e.message}", android.widget.Toast.LENGTH_LONG).show()
            
            // Close after 3 seconds even if error
            Handler(Looper.getMainLooper()).postDelayed({
                finish()
            }, 3000)
        }
    }
    
    private fun showVibrationPhase() {
        if (isCancelled) {
            Log.d(TAG, "🛑 Vibration phase cancelled")
            return
        }
        
        Log.d(TAG, "📳 Starting 7-second vibration phase")
        
        // Update UI for vibration phase
        layout.setBackgroundColor(android.graphics.Color.parseColor("#FFA500")) // Orange
        titleText.text = "📳 VIBRATING"
        messageText.text = "Emergency alert active - Last chance to cancel!"
        countdownText.text = "7"
        countdownText.textSize = 100f
        triggerText.text = "Vibrating for 7 seconds..."
        
        // Keep cancel button visible during vibration
        cancelButton.visibility = android.view.View.VISIBLE
        cancelButton.text = "CANCEL NOW"
        cancelButton.setBackgroundColor(android.graphics.Color.WHITE)
        cancelButton.setTextColor(android.graphics.Color.parseColor("#FFA500"))
        
        // Start vibration
        startVibration()
        
        // Countdown for vibration phase - store runnable so we can cancel it
        var vibrateSeconds = 7
        vibrationRunnable = object : Runnable {
            override fun run() {
                if (isCancelled) {
                    Log.d(TAG, "🛑 Vibration countdown cancelled")
                    vibrationHandler.removeCallbacks(this)
                    return
                }
                
                vibrateSeconds--
                countdownText.text = vibrateSeconds.toString()
                Log.d(TAG, "📳 Vibration countdown: $vibrateSeconds")
                
                if (vibrateSeconds > 0) {
                    vibrationHandler.postDelayed(this, 1000)
                } else {
                    Log.d(TAG, "📳 Vibration finished - sending SMS")
                    sendSOSAndClose()
                }
            }
        }
        vibrationHandler.postDelayed(vibrationRunnable!!, 1000)
    }
    
    private fun startVibration() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            
            // Vibrate continuously for 7 seconds: 500ms on, 200ms off pattern
            val pattern = longArrayOf(0, 500, 200, 500, 200, 500, 200, 500, 200, 500, 200, 500, 200, 500)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, -1)
            }
            
            Log.d(TAG, "✅ Vibration started")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Vibration error: ${e.message}")
        }
    }
    
    private var locationSMSTimer: java.util.Timer? = null

    private fun startRepeatingLocationSMS(contacts: List<Map<String, String>>, smsManager: SmsManager) {
        locationSMSTimer?.cancel()
        locationSMSTimer = java.util.Timer()
        locationSMSTimer?.scheduleAtFixedRate(object : java.util.TimerTask() {
            override fun run() {
                if (isCancelled) {
                    cancel()
                    return
                }
                fetchLocationAndSendSMS(contacts, smsManager)
            }
        }, 60000L, 60000L) // Start after 60s, repeat every 60s
        Log.d(TAG, "✅ Repeating location SMS started (every 60s)")
    }

    private fun fetchLocationAndSendSMS(contacts: List<Map<String, String>>, smsManager: SmsManager) {
        try {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
            if (checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) != android.content.pm.PackageManager.PERMISSION_GRANTED) return

            val location = locationManager.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)
                ?: locationManager.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)

            val locationText = if (location != null)
                "https://maps.google.com/?q=${location.latitude},${location.longitude}"
            else "Location unavailable"

            val message = "🚨 LIVE LOCATION UPDATE - I still need help!\n📍 $locationText\n- Raksha Safety App"

            for (contact in contacts) {
                val phone = contact["phone"] ?: continue
                if (phone.isNotEmpty()) {
                    try {
                        smsManager.sendTextMessage(phone, null, message, null, null)
                        Log.d(TAG, "✅ Location SMS sent to $phone")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to send location SMS: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending location SMS: ${e.message}")
        }
    }

    private fun cancelSOS() {
        if (isCancelled) {
            Log.d(TAG, "🛑 Already cancelled")
            return
        }
        
        Log.d(TAG, "🛑 SOS Cancelled by user")
        isCancelled = true
        
        // Cancel countdown timer
        countDownTimer?.cancel()
        
        // Remove ALL pending callbacks immediately
        vibrationRunnable?.let { vibrationHandler.removeCallbacks(it) }
        vibrationHandler.removeCallbacksAndMessages(null)
        
        // Stop vibration immediately
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator.cancel()
        } catch (e: Exception) { }
        
        // Cancel location SMS timer
        locationSMSTimer?.cancel()
        locationSMSTimer = null
        
        // Stop SOSNotificationService too
        stopService(Intent(this, SOSNotificationService::class.java))
        
        // Stop StealthRecordingService
        val stopRecording = Intent(this, StealthRecordingService::class.java).apply {
            action = "STOP_STEALTH_RECORDING"
        }
        startService(stopRecording)
        
        android.widget.Toast.makeText(this, "🛑 SOS Cancelled", android.widget.Toast.LENGTH_LONG).show()
        finish()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "🛑 SOSCountdownActivity destroyed")
        
        // Release wake lock
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d(TAG, "✅ Wake lock released")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing wake lock: ${e.message}")
        }
        
        // Cancel all timers and callbacks
        countDownTimer?.cancel()
        locationSMSTimer?.cancel()
        vibrationRunnable?.let {
            vibrationHandler.removeCallbacks(it)
        }
        
        // Stop vibration
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping vibration in onDestroy: ${e.message}")
        }
        
        // cancelReceiver was never registered in this activity — skip unregister.
    }

    override fun onBackPressed() {
        // Prevent back button from closing during countdown
        if (secondsRemaining > 0) {
            android.widget.Toast.makeText(this, "Use CANCEL button to stop SOS", android.widget.Toast.LENGTH_SHORT).show()
        } else {
            super.onBackPressed()
        }
    }
}
