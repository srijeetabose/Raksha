package com.example.raksha

import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import kotlin.math.sqrt

/**
 * Detects phone shake gesture as emergency trigger
 * Alternative to voice detection for Android 15
 */
class ShakeDetector(private val context: Context) : SensorEventListener {
    
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var shakeListener: (() -> Unit)? = null
    
    private var lastShakeTime = 0L
    private val SHAKE_THRESHOLD = 15.0f // Sensitivity
    private val SHAKE_COOLDOWN = 3000L // 3 seconds between shakes
    
    private val TAG = "ShakeDetector"
    
    fun start(onShake: () -> Unit) {
        shakeListener = onShake
        
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        
        if (accelerometer != null) {
            sensorManager?.registerListener(
                this,
                accelerometer,
                SensorManager.SENSOR_DELAY_NORMAL
            )
            Log.d(TAG, "✅ Shake detector started")
        } else {
            Log.e(TAG, "❌ No accelerometer found")
        }
    }
    
    fun stop() {
        sensorManager?.unregisterListener(this)
        Log.d(TAG, "🛑 Shake detector stopped")
    }
    
    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_ACCELEROMETER) {
            val x = event.values[0]
            val y = event.values[1]
            val z = event.values[2]
            
            // Calculate acceleration magnitude
            val acceleration = sqrt((x * x + y * y + z * z).toDouble()).toFloat()
            
            // Remove gravity
            val accelerationWithoutGravity = acceleration - SensorManager.GRAVITY_EARTH
            
            // Check if shake detected
            if (accelerationWithoutGravity > SHAKE_THRESHOLD) {
                val currentTime = System.currentTimeMillis()
                
                // Prevent multiple triggers
                if (currentTime - lastShakeTime > SHAKE_COOLDOWN) {
                    lastShakeTime = currentTime
                    Log.d(TAG, "🚨 SHAKE DETECTED! Acceleration: $accelerationWithoutGravity")
                    shakeListener?.invoke()
                }
            }
        }
    }
    
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed
    }
}
