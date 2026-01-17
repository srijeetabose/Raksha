// android/app/src/main/kotlin/com/example/raksha/StealthRecordingService.kt

package com.example.raksha

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.core.app.NotificationCompat
import java.io.File

class StealthRecordingService : Service() {
    
    private var cameraManager: CameraManager? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var mediaRecorder: MediaRecorder? = null
    private var recordingId: String? = null
    
    companion object {
        private const val NOTIFICATION_ID = 9999
        private const val CHANNEL_ID = "stealth_recording"
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START_STEALTH_RECORDING" -> {
                recordingId = intent.getStringExtra("recordingId")
                val gesture = intent.getStringExtra("gesture") ?: "Unknown"
                val timestamp = intent.getLongExtra("timestamp", System.currentTimeMillis())
                val outputPath = intent.getStringExtra("outputPath")
                
                startStealthRecording(gesture, timestamp, outputPath)
            }
            "STOP_STEALTH_RECORDING" -> {
                stopStealthRecording()
            }
        }
        
        return START_STICKY // Keep service running
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Emergency Recording",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background emergency recording service"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private var outputFilePath: String? = null
    
    private fun startStealthRecording(gesture: String, timestamp: Long, outputPath: String?) {
        try {
            Log.d("StealthRecording", "🎥 Starting SECURE VAULT video recording")
            outputFilePath = outputPath
            
            // Create invisible notification (required for foreground service)
            val notification = createInvisibleNotification()
            startForeground(NOTIFICATION_ID, notification)
            
            // Start camera recording
            setupCameraAndStartRecording()
            
        } catch (e: Exception) {
            Log.e("StealthRecording", "❌ Error starting stealth recording: ${e.message}")
        }
    }
    
    private fun createInvisibleNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("System Service")
            .setContentText("Background service running")
            .setSmallIcon(android.R.drawable.ic_media_play) // Use system icon
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }
    
    private fun setupCameraAndStartRecording() {
        try {
            val cameraId = getFrontCameraId()
            if (cameraId == null) {
                Log.e("StealthRecording", "❌ No front camera found")
                return
            }
            
            cameraManager?.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    startRecordingSession()
                }
                
                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                }
                
                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e("StealthRecording", "❌ Camera error: $error")
                    camera.close()
                    cameraDevice = null
                }
            }, null)
            
        } catch (e: Exception) {
            Log.e("StealthRecording", "❌ Error setting up camera: ${e.message}")
        }
    }
    
    private fun getFrontCameraId(): String? {
        try {
            for (cameraId in cameraManager?.cameraIdList ?: emptyArray()) {
                val characteristics = cameraManager?.getCameraCharacteristics(cameraId)
                val facing = characteristics?.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
                    return cameraId
                }
            }
        } catch (e: Exception) {
            Log.e("StealthRecording", "❌ Error finding front camera: ${e.message}")
        }
        return null
    }
    
    private fun startRecordingSession() {
        try {
            // Setup MediaRecorder
            mediaRecorder = MediaRecorder().apply {
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoSize(640, 480) // Lower resolution for stealth
                setVideoFrameRate(15) // Lower frame rate to save battery
                
                // Save to secure vault directory
                val videoFile = if (outputFilePath != null) {
                    File(outputFilePath)
                } else {
                    // Fallback to secure vault directory
                    val secureVaultDir = File(filesDir, ".secure_vault")
                    if (!secureVaultDir.exists()) {
                        secureVaultDir.mkdirs()
                    }
                    File(secureVaultDir, "${recordingId}_video.mp4")
                }
                
                Log.d("StealthRecording", "📹 Saving video to: ${videoFile.absolutePath}")
                setOutputFile(videoFile.absolutePath)
                
                prepare()
            }
            
            // Create capture session
            val surface = mediaRecorder?.surface
            val surfaceTexture = SurfaceTexture(0)
            val previewSurface = Surface(surfaceTexture)
            
            val surfaces = listOf(surface, previewSurface).filterNotNull()
            
            cameraDevice?.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    
                    // Start recording
                    mediaRecorder?.start()
                    Log.d("StealthRecording", "✅ Stealth video recording started")
                }
                
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e("StealthRecording", "❌ Failed to configure capture session")
                }
            }, null)
            
        } catch (e: Exception) {
            Log.e("StealthRecording", "❌ Error starting recording session: ${e.message}")
        }
    }
    
    private fun stopStealthRecording() {
        try {
            Log.d("StealthRecording", "🛑 Stopping stealth recording")
            
            // Stop recording
            mediaRecorder?.apply {
                stop()
                release()
            }
            mediaRecorder = null
            
            // Close camera
            captureSession?.close()
            cameraDevice?.close()
            
            // Stop foreground service
            stopForeground(true)
            stopSelf()
            
            Log.d("StealthRecording", "✅ Stealth recording stopped")
        } catch (e: Exception) {
            Log.e("StealthRecording", "❌ Error stopping stealth recording: ${e.message}")
        }
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        super.onDestroy()
        stopStealthRecording()
    }
}