package com.example.raksha

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import java.io.File

class StealthRecordingService : Service() {

    private var mediaRecorder: MediaRecorder? = null
    private var audioRecorder: MediaRecorder? = null
    private var cameraDevice: android.hardware.camera2.CameraDevice? = null
    private var captureSession: android.hardware.camera2.CameraCaptureSession? = null
    private var recordingId: String? = null
    private var gesture: String? = null
    private var audioFilePath: String? = null
    private var videoFilePath: String? = null

    companion object {
        private const val TAG = "StealthRecording"
        private const val NOTIFICATION_ID = 8888
        private const val CHANNEL_ID = "stealth_recording"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        Log.d(TAG, " StealthRecordingService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START_STEALTH_RECORDING" -> {
                recordingId = intent.getStringExtra("recordingId")
                gesture = intent.getStringExtra("gesture") ?: "Unknown"
                val timestamp = intent.getLongExtra("timestamp", System.currentTimeMillis())
                startRecording(timestamp)
            }
            "STOP_STEALTH_RECORDING" -> stopRecording()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startRecording(timestamp: Long) {
        try {
            val secureVaultDir = File(filesDir, ".secure_vault")
            if (!secureVaultDir.exists()) secureVaultDir.mkdirs()

            audioFilePath = File(secureVaultDir, "${recordingId}_audio.m4a").absolutePath
            videoFilePath = File(secureVaultDir, "${recordingId}_video.mp4").absolutePath

            Log.d(TAG, " Audio: $audioFilePath")
            Log.d(TAG, " Video: $videoFilePath")

            // Start audio recording
            startAudioRecording()

            // Start video recording
            startVideoRecording()

            // Save metadata
            saveMetadataToFirebase(timestamp)

            Log.d(TAG, " Recording started")
        } catch (e: Exception) {
            Log.e(TAG, " Error starting recording: ${e.message}")
        }
    }

    private fun startAudioRecording() {
        try {
            audioRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            audioRecorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setOutputFile(audioFilePath)
                prepare()
                start()
                Log.d(TAG, " Audio recording started")
            }
        } catch (e: Exception) {
            Log.e(TAG, " Audio recording error: ${e.message}")
        }
    }

    private fun startVideoRecording() {
        try {
            // Check camera permission
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (checkSelfPermission(android.Manifest.permission.CAMERA)
                    != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    Log.e(TAG, " Camera permission not granted")
                    return
                }
            }

            val cameraId = getFrontOrBackCameraId()
            if (cameraId == null) {
                Log.e(TAG, " No camera found")
                return
            }

            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            mediaRecorder?.apply {
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoSize(640, 480)
                setVideoFrameRate(15)
                setVideoEncodingBitRate(1000000)
                setOutputFile(videoFilePath)
                prepare()
            }

            // Use Camera2 to feed frames into MediaRecorder surface
            val camManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            camManager.openCamera(cameraId, object : android.hardware.camera2.CameraDevice.StateCallback() {
                override fun onOpened(camera: android.hardware.camera2.CameraDevice) {
                    cameraDevice = camera
                    try {
                        val surface = mediaRecorder!!.surface
                        val dummy = android.graphics.SurfaceTexture(0)
                        val dummySurface = android.view.Surface(dummy)
                        val surfaces = listOf(surface, dummySurface)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            val configs = surfaces.map {
                                android.hardware.camera2.params.OutputConfiguration(it)
                            }
                            val sessionConfig = android.hardware.camera2.params.SessionConfiguration(
                                android.hardware.camera2.params.SessionConfiguration.SESSION_REGULAR,
                                configs,
                                mainExecutor,
                                object : android.hardware.camera2.CameraCaptureSession.StateCallback() {
                                    override fun onConfigured(session: android.hardware.camera2.CameraCaptureSession) {
                                        captureSession = session
                                        try {
                                            // CRITICAL: must create capture request to send frames to surface
                                            val captureRequest = camera.createCaptureRequest(
                                                android.hardware.camera2.CameraDevice.TEMPLATE_RECORD
                                            ).apply {
                                                addTarget(surface)
                                            }.build()
                                            session.setRepeatingRequest(captureRequest, null, null)
                                            mediaRecorder?.start()
                                            Log.d(TAG, " Video recording started")
                                        } catch (e: Exception) {
                                            Log.e(TAG, " Failed to start video: ${e.message}")
                                        }
                                    }
                                    override fun onConfigureFailed(session: android.hardware.camera2.CameraCaptureSession) {
                                        Log.e(TAG, " Camera session config failed")
                                    }
                                }
                            )
                            camera.createCaptureSession(sessionConfig)
                        } else {
                            @Suppress("DEPRECATION")
                            camera.createCaptureSession(surfaces, object : android.hardware.camera2.CameraCaptureSession.StateCallback() {
                                override fun onConfigured(session: android.hardware.camera2.CameraCaptureSession) {
                                    try {
                                        val captureRequest = camera.createCaptureRequest(
                                            android.hardware.camera2.CameraDevice.TEMPLATE_RECORD
                                        ).apply {
                                            addTarget(surface)
                                        }.build()
                                        session.setRepeatingRequest(captureRequest, null, null)
                                        mediaRecorder?.start()
                                        Log.d(TAG, " Video recording started (legacy)")
                                    } catch (e: Exception) {
                                        Log.e(TAG, " Failed to start video: ${e.message}")
                                    }
                                }
                                override fun onConfigureFailed(session: android.hardware.camera2.CameraCaptureSession) {
                                    Log.e(TAG, " Camera session config failed")
                                }
                            }, null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, " Camera setup error: ${e.message}")
                    }
                }
                override fun onDisconnected(camera: android.hardware.camera2.CameraDevice) {
                    camera.close()
                }
                override fun onError(camera: android.hardware.camera2.CameraDevice, error: Int) {
                    Log.e(TAG, " Camera error: $error")
                    camera.close()
                }
            }, null)

        } catch (e: Exception) {
            Log.e(TAG, " Video recording error: ${e.message}")
        }
    }

    private fun getFrontOrBackCameraId(): String? {
        val camManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        // Back camera first (as requested)
        for (id in camManager.cameraIdList) {
            val facing = camManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_BACK) return id
        }
        // Fall back to front
        for (id in camManager.cameraIdList) {
            val facing = camManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_FRONT) return id
        }
        return camManager.cameraIdList.firstOrNull()
    }

    private fun stopRecording() {
        try {
            audioRecorder?.apply { stop(); release() }
            audioRecorder = null
            Log.d(TAG, " Audio stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Audio stop error: ${e.message}")
        }
        try {
            captureSession?.close()
            captureSession = null
        } catch (e: Exception) { }
        try {
            cameraDevice?.close()
            cameraDevice = null
        } catch (e: Exception) { }
        try {
            mediaRecorder?.apply { stop(); release() }
            mediaRecorder = null
            Log.d(TAG, " Video stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Video stop error: ${e.message}")
        }
        updateFirebaseStatus()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun saveMetadataToFirebase(timestamp: Long) {
        try {
            val userId = FirebaseAuth.getInstance().currentUser?.uid ?: return
            val data = hashMapOf(
                "id" to recordingId,
                "gesture" to gesture,
                "startTime" to timestamp,
                "hasAudio" to true,
                "hasVideo" to true,
                "status" to "recording",
                "audioPath" to audioFilePath,
                "videoPath" to videoFilePath
            )
            FirebaseFirestore.getInstance()
                .collection("users").document(userId)
                .collection("secureVaultRecordings").document(recordingId!!)
                .set(data)
                .addOnSuccessListener { Log.d(TAG, " Metadata saved") }
                .addOnFailureListener { Log.e(TAG, " Metadata save failed: ${it.message}") }
        } catch (e: Exception) {
            Log.e(TAG, "Metadata error: ${e.message}")
        }
    }

    private fun updateFirebaseStatus() {
        try {
            val userId = FirebaseAuth.getInstance().currentUser?.uid ?: return
            if (recordingId == null) return
            FirebaseFirestore.getInstance()
                .collection("users").document(userId)
                .collection("secureVaultRecordings").document(recordingId!!)
                .update(mapOf("status" to "completed", "endTime" to System.currentTimeMillis()))
        } catch (e: Exception) {
            Log.e(TAG, "Status update error: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Emergency Recording", NotificationManager.IMPORTANCE_MIN
            ).apply { setShowBadge(false); setSound(null, null) }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("System Service")
            .setContentText("Running")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRecording()
    }
}
