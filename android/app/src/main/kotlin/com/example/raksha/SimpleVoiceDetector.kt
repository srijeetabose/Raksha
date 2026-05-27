package com.example.raksha

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Simple always-on voice detector that works by detecting voice activity patterns
 * This bypasses Android's unreliable SpeechRecognizer
 */
class SimpleVoiceDetector(
    private val onVoiceDetected: () -> Unit
) {
    private val TAG = "SimpleVoiceDetector"
    private var audioRecord: AudioRecord? = null
    private var isRunning = false
    private var detectionThread: Thread? = null
    
    private val SAMPLE_RATE = 16000
    private val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
    private val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    
    // Detection thresholds - LOWERED for better detection
    private val VOICE_THRESHOLD = 1200 // Amplitude threshold for voice (lowered from 1500)
    private val SILENCE_THRESHOLD = 500 // Amplitude threshold for silence
    private val MIN_VOICE_DURATION_MS = 400 // Minimum voice duration (lowered from 800)
    private val MAX_VOICE_DURATION_MS = 4000 // Maximum voice duration (increased from 3000)
    private val MIN_FRAMES = 3 // Minimum frames (lowered from 10)
    private val COOLDOWN_MS = 3000 // Cooldown between detections
    
    private var lastDetectionTime = 0L
    
    fun start() {
        if (isRunning) {
            Log.w(TAG, "Already running")
            return
        }
        
        try {
            val bufferSize = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT
            ) * 2
            
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize
            )
            
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord initialization failed")
                return
            }
            
            audioRecord?.startRecording()
            isRunning = true
            
            detectionThread = Thread {
                detectVoicePatterns(bufferSize)
            }
            detectionThread?.start()
            
            Log.d(TAG, " Simple voice detector started")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting detector: ${e.message}")
            e.printStackTrace()
        }
    }
    
    fun stop() {
        isRunning = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            detectionThread?.join(1000)
            Log.d(TAG, "Voice detector stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping detector: ${e.message}")
        }
    }
    
    private fun detectVoicePatterns(bufferSize: Int) {
        val audioBuffer = ShortArray(bufferSize)
        var voiceStartTime = 0L
        var isVoiceActive = false
        var consecutiveVoiceFrames = 0
        
        Log.d(TAG, "� Voice pattern detection thread started")
        
        while (isRunning) {
            try {
                val readSize = audioRecord?.read(audioBuffer, 0, bufferSize) ?: 0
                
                if (readSize > 0) {
                    // Calculate RMS (Root Mean Square) amplitude
                    val rms = calculateRMS(audioBuffer, readSize)
                    
                    val currentTime = System.currentTimeMillis()
                    
                    // Check if voice is detected
                    if (rms > VOICE_THRESHOLD) {
                        if (!isVoiceActive) {
                            // Voice started
                            voiceStartTime = currentTime
                            isVoiceActive = true
                            consecutiveVoiceFrames = 1
                            Log.d(TAG, "� Voice activity started (RMS: $rms)")
                        } else {
                            consecutiveVoiceFrames++
                        }
                    } else if (rms < SILENCE_THRESHOLD && isVoiceActive) {
                        // Voice ended
                        val voiceDuration = currentTime - voiceStartTime
                        
                        Log.d(TAG, "� Voice ended. Duration: ${voiceDuration}ms, Frames: $consecutiveVoiceFrames")
                        
                        // Check if voice duration matches expected pattern
                        if (voiceDuration >= MIN_VOICE_DURATION_MS && 
                            voiceDuration <= MAX_VOICE_DURATION_MS &&
                            consecutiveVoiceFrames >= MIN_FRAMES) {
                            
                            // Check cooldown
                            if (currentTime - lastDetectionTime > COOLDOWN_MS) {
                                Log.d(TAG, " VOICE PATTERN DETECTED! Duration: ${voiceDuration}ms, Frames: $consecutiveVoiceFrames")
                                lastDetectionTime = currentTime
                                
                                // Trigger callback on main thread
                                android.os.Handler(android.os.Looper.getMainLooper()).post {
                                    onVoiceDetected()
                                }
                            } else {
                                Log.d(TAG, "⏰ In cooldown period, ignoring")
                            }
                        } else {
                            Log.d(TAG, " Voice too short/long or not enough frames: ${voiceDuration}ms, $consecutiveVoiceFrames frames")
                        }
                        
                        isVoiceActive = false
                        consecutiveVoiceFrames = 0
                    }
                }
                
                // Small delay to prevent CPU overload
                Thread.sleep(50)
                
            } catch (e: Exception) {
                Log.e(TAG, "Error in detection loop: ${e.message}")
                break
            }
        }
        
        Log.d(TAG, "Voice pattern detection thread stopped")
    }
    
    private fun calculateRMS(buffer: ShortArray, size: Int): Double {
        var sum = 0.0
        for (i in 0 until size) {
            sum += (buffer[i] * buffer[i]).toDouble()
        }
        return sqrt(sum / size)
    }
}
