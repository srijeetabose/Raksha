/*
 * Copyright 2022 The TensorFlow Authors. All Rights Reserved.
 * Adapted for Raksha Safety App
 */
package com.example.raksha

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import android.util.Log
import androidx.annotation.VisibleForTesting
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult

class GestureRecognizerHelper(
        var minHandDetectionConfidence: Float = DEFAULT_HAND_DETECTION_CONFIDENCE,
        var minHandTrackingConfidence: Float = DEFAULT_HAND_TRACKING_CONFIDENCE,
        var minHandPresenceConfidence: Float = DEFAULT_HAND_PRESENCE_CONFIDENCE,
        var currentDelegate: Int = DELEGATE_CPU,
        var runningMode: RunningMode = RunningMode.IMAGE,
        val context: Context,
        val gestureRecognizerListener: GestureRecognizerListener? = null
) {

    // For this example this needs to be a var so it can be reset on changes. If the
    // GestureRecognizer
    // will not change, a lazy val would be preferable.
    private var gestureRecognizer: GestureRecognizer? = null

    init {
        Log.d(TAG, "🚀 GestureRecognizerHelper init() called")
        try {
            setupGestureRecognizer()
            Log.d(TAG, "✅ setupGestureRecognizer() completed in init")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception in init: ${e.message}")
            e.printStackTrace()
        }
    }

    fun clearGestureRecognizer() {
        gestureRecognizer?.close()
        gestureRecognizer = null
    }

    fun isInitialized(): Boolean {
        return gestureRecognizer != null
    }

    fun forceReinitialize() {
        Log.d(TAG, "🔄 Force reinitializing GestureRecognizer...")
        clearGestureRecognizer()
        setupGestureRecognizer()
    }

    // Initialize the gesture recognizer using current settings on the
    // thread that is using it. CPU can be used with recognizers
    // that are created on the main thread and used on a background thread, but
    // the GPU delegate needs to be used on the thread that initialized the recognizer
    fun setupGestureRecognizer() {
        Log.d(TAG, "🚀 Starting MediaPipe GestureRecognizer setup...")

        // Clear any existing recognizer
        gestureRecognizer?.close()
        gestureRecognizer = null

        try {
            // Set general recognition options, including number of used threads
            val baseOptionBuilder = BaseOptions.builder()

            // Use CPU delegate for better compatibility
            Log.d(TAG, "📱 Using CPU delegate for MediaPipe")
            baseOptionBuilder.setDelegate(Delegate.CPU)

            // Set model path with validation
            Log.d(TAG, "📁 Setting model path: $MP_RECOGNIZER_TASK")

            // Check if model file exists
            try {
                val inputStream = context.assets.open(MP_RECOGNIZER_TASK)
                val fileSize = inputStream.available()
                inputStream.close()
                Log.d(TAG, "✅ Model file found, size: $fileSize bytes")

                if (fileSize < 1000000) { // Less than 1MB is suspicious
                    Log.w(TAG, "⚠️ Model file seems too small: $fileSize bytes")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Model file not found: ${e.message}")
                // Try alternative path
                try {
                    Log.d(TAG, "🔄 Trying alternative model path...")
                    val altInputStream = context.assets.open("gesture_recognizer_official.task")
                    altInputStream.close()
                    baseOptionBuilder.setModelAssetPath("gesture_recognizer_official.task")
                    Log.d(TAG, "✅ Using alternative model file")
                } catch (e2: Exception) {
                    Log.e(TAG, "❌ Alternative model also not found: ${e2.message}")
                    throw e
                }
            }

            baseOptionBuilder.setModelAssetPath(MP_RECOGNIZER_TASK)

            val baseOptions = baseOptionBuilder.build()
            Log.d(TAG, "✅ BaseOptions created successfully")

            val optionsBuilder =
                    GestureRecognizer.GestureRecognizerOptions.builder()
                            .setBaseOptions(baseOptions)
                            .setMinHandDetectionConfidence(0.3f) // Much lower threshold
                            .setMinTrackingConfidence(0.3f)
                            .setMinHandPresenceConfidence(0.3f)
                            .setRunningMode(runningMode) // Use configured running mode
            
            // CRITICAL: Set result listener for LIVE_STREAM mode
            if (runningMode == RunningMode.LIVE_STREAM) {
                optionsBuilder.setResultListener(this::returnLivestreamResult)
                        .setErrorListener(this::returnLivestreamError)
                Log.d(TAG, "🔧 LIVE_STREAM mode with result listener configured")
            } else {
                Log.d(TAG, "🔧 IMAGE mode configured")
            }

            Log.d(TAG, "🔧 GestureRecognizerOptions configured")

            val options = optionsBuilder.build()
            Log.d(TAG, "✅ Options built successfully")

            gestureRecognizer = GestureRecognizer.createFromOptions(context, options)

            if (gestureRecognizer != null) {
                Log.d(TAG, "🎉 MediaPipe GestureRecognizer initialized successfully!")
            } else {
                Log.e(TAG, "❌ GestureRecognizer is null after creation")
            }
        } catch (e: IllegalStateException) {
            Log.e(TAG, "❌ IllegalStateException during setup: ${e.message}")
            e.printStackTrace()
            gestureRecognizerListener?.onError(
                    "Gesture recognizer failed to initialize: ${e.message}",
                    1
            )
        } catch (e: RuntimeException) {
            Log.e(TAG, "❌ RuntimeException during setup: ${e.message}")
            e.printStackTrace()
            gestureRecognizerListener?.onError(
                    "Gesture recognizer failed to initialize: ${e.message}",
                    GPU_ERROR
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ Unexpected exception during setup: ${e.message}")
            e.printStackTrace()
            gestureRecognizerListener?.onError(
                    "Gesture recognizer failed to initialize: ${e.message}",
                    2
            )
        }
    }

    // Convert the ImageProxy to MP Image and feed it to GestureRecognizer.
    fun recognizeLiveStream(imageProxy: ImageProxy) {
        val frameTime = SystemClock.uptimeMillis()

        // Copy out RGB bits from the frame to a bitmap buffer
        val bitmapBuffer =
                Bitmap.createBitmap(imageProxy.width, imageProxy.height, Bitmap.Config.ARGB_8888)
        bitmapBuffer.copyPixelsFromBuffer(imageProxy.planes[0].buffer)
        imageProxy.close()

        val matrix =
                Matrix().apply {
                    // Rotate the frame received from the camera to be in the same direction as
                    // it'll be shown
                    postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())

                    // flip image since we only support front camera
                    postScale(-1f, 1f, imageProxy.width.toFloat(), imageProxy.height.toFloat())
                }

        // Rotate bitmap to match what our model expects
        val rotatedBitmap =
                Bitmap.createBitmap(
                        bitmapBuffer,
                        0,
                        0,
                        bitmapBuffer.width,
                        bitmapBuffer.height,
                        matrix,
                        true
                )

        // Convert the input Bitmap object to an MPImage object to run inference
        val mpImage = BitmapImageBuilder(rotatedBitmap).build()

        recognizeAsync(mpImage, frameTime)
    }

    // Run hand gesture recognition using MediaPipe Gesture Recognition API
    @VisibleForTesting
    fun recognizeAsync(mpImage: MPImage, frameTime: Long) {
        // As we're using running mode LIVE_STREAM, the recognition result will
        // be returned in returnLivestreamResult function
        gestureRecognizer?.recognizeAsync(mpImage, frameTime)
    }

    // Accepted a Bitmap and runs gesture recognizer inference on it to
    // return results back to the caller
    fun recognizeImage(image: Bitmap): ResultBundle? {
        if (runningMode != RunningMode.IMAGE) {
            throw IllegalArgumentException(
                    "Attempting to call detectImage while not using RunningMode.IMAGE"
            )
        }

        // Check if gesture recognizer is initialized
        if (gestureRecognizer == null) {
            Log.e(TAG, "❌ GestureRecognizer is null - not initialized properly")
            gestureRecognizerListener?.onError("Gesture Recognizer not initialized")
            return null
        }

        // Validate input bitmap
        if (image.isRecycled) {
            Log.e(TAG, "❌ Input bitmap is recycled")
            gestureRecognizerListener?.onError("Input bitmap is recycled")
            return null
        }

        Log.d(TAG, "🎯 Processing image: ${image.width}x${image.height}, config: ${image.config}")

        try {
            // Inference time is the difference between the system time at the
            // start and finish of the process
            val startTime = SystemClock.uptimeMillis()

            // Convert the input Bitmap object to an MPImage object to run inference
            val mpImage = BitmapImageBuilder(image).build()
            Log.d(TAG, "✅ MPImage created successfully")

            // Run gesture recognizer using MediaPipe Gesture Recognizer API
            val recognizerResult = gestureRecognizer!!.recognize(mpImage)

            if (recognizerResult != null) {
                val inferenceTimeMs = SystemClock.uptimeMillis() - startTime
                Log.d(TAG, "✅ MediaPipe recognition completed in ${inferenceTimeMs}ms")

                // Process the result for our Raksha emergency detection
                processGestureResultForRaksha(recognizerResult)

                return ResultBundle(
                        listOf(recognizerResult),
                        inferenceTimeMs,
                        image.height,
                        image.width
                )
            } else {
                Log.w(TAG, "⚠️ MediaPipe returned null result - no gestures detected")
                return ResultBundle(
                        emptyList(),
                        SystemClock.uptimeMillis() - startTime,
                        image.height,
                        image.width
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception during gesture recognition: ${e.message}")
            e.printStackTrace()
            gestureRecognizerListener?.onError("Gesture recognition failed: ${e.message}")
            return null
        }
    }

    // Process gesture results for Raksha emergency detection
    private fun processGestureResultForRaksha(result: GestureRecognizerResult) {
        Log.d(TAG, "📊 Processing REAL MediaPipe result for Raksha...")

        if (result.gestures().isNotEmpty()) {
            Log.d(TAG, "🎯 Found ${result.gestures().size} gesture categories")

            val topGesture = result.gestures()[0]
            if (topGesture.isNotEmpty()) {
                val gesture = topGesture[0]
                val confidence = gesture.score()
                val gestureName = gesture.categoryName()

                // LOG ALL DETECTED GESTURES FOR DEBUGGING
                Log.d(
                        TAG,
                        "🔍 RAW MediaPipe Detection: '$gestureName' (confidence: ${(confidence * 100).toInt()}%)"
                )

                // Store result for MainActivity to access
                gestureRecognizerListener?.onResults(ResultBundle(listOf(result), 0, 0, 0))

                // Map MediaPipe gesture names to our Raksha gesture names
                val mappedGesture = mapGestureNameForRaksha(gestureName)

                // Only trigger on high confidence gestures
                if (mappedGesture != "Unknown" && confidence > 0.7f) {
                    Log.d(
                            TAG,
                            "✅ HIGH CONFIDENCE RAKSHA GESTURE DETECTED: $mappedGesture (original: '$gestureName', confidence: ${(confidence * 100).toInt()}%)"
                    )

                    // Notify Raksha listeners about the detected gesture
                    notifyRakshaGestureDetected(mappedGesture, confidence)
                } else if (mappedGesture == "Unknown") {
                    Log.d(
                            TAG,
                            "⚪ Unknown gesture ignored: $gestureName (${(confidence * 100).toInt()}%)"
                    )
                } else {
                    Log.d(
                            TAG,
                            "⚪ Low confidence gesture: $gestureName (${(confidence * 100).toInt()}%) - threshold is 70%"
                    )
                }

                // Log ALL gestures in the result for debugging
                for (i in 0 until minOf(topGesture.size, 3)) {
                    val g = topGesture[i]
                    Log.d(TAG, "  Gesture $i: ${g.categoryName()} (${(g.score() * 100).toInt()}%)")
                }
            } else {
                Log.d(TAG, "⚠️ Top gesture category is empty")
            }
        } else {
            Log.d(TAG, "👁️ No gestures detected in this frame")
        }
    }

    private fun mapGestureNameForRaksha(originalName: String): String {
        return when (originalName.lowercase()) {
            // Standard MediaPipe gesture labels (exact matches)
            "victory" -> "Victory"
            "thumb_up" -> "Thumb_Up"
            "thumb_down" -> "Thumb_Down"
            "closed_fist" -> "Closed_Fist"

            // Alternative exact labels that MediaPipe might use
            "peace" -> "Victory"
            "peace_sign" -> "Victory"
            "v_sign" -> "Victory"
            "thumbs_up" -> "Thumb_Up"
            "thumbs_down" -> "Thumb_Down"
            "fist" -> "Closed_Fist"

            // STRICT MAPPING - Only accept known gestures for Raksha
            else -> {
                Log.w(
                        TAG,
                        "🔍 UNKNOWN/UNMAPPED GESTURE: '$originalName' - Ignoring for Raksha accuracy"
                )
                "Unknown" // Return Unknown instead of the original name
            }
        }
    }

    private fun notifyRakshaGestureDetected(gestureName: String, confidence: Float) {
        // Create a custom result bundle for Raksha
        val customResult =
                ResultBundle(
                        results = emptyList(), // We don't need the full result for Raksha
                        inferenceTime = 0L,
                        inputImageHeight = 0,
                        inputImageWidth = 0
                )

        // Notify the listener
        gestureRecognizerListener?.onResults(customResult)

        // Also log for Raksha debugging
        Log.d(TAG, "🚨 RAKSHA GESTURE NOTIFICATION: $gestureName (${(confidence * 100).toInt()}%)")
    }

    // Return running status of the recognizer helper
    fun isClosed(): Boolean {
        return gestureRecognizer == null
    }

    // Return the recognition result to the GestureRecognizerHelper's caller
    private fun returnLivestreamResult(result: GestureRecognizerResult, input: MPImage) {
        val finishTimeMs = SystemClock.uptimeMillis()
        val inferenceTime = finishTimeMs - result.timestampMs()

        // Process the result for Raksha emergency detection
        processGestureResultForRaksha(result)

        gestureRecognizerListener?.onResults(
                ResultBundle(listOf(result), inferenceTime, input.height, input.width)
        )
    }

    // Return errors thrown during recognition to this GestureRecognizerHelper's
    // caller
    private fun returnLivestreamError(error: RuntimeException) {
        gestureRecognizerListener?.onError(error.message ?: "An unknown error has occurred")
    }

    companion object {
        val TAG = "RakshaGestureHelper"
        private const val MP_RECOGNIZER_TASK = "gesture_recognizer.task"

        const val DELEGATE_CPU = 0
        const val DELEGATE_GPU = 1
        const val DEFAULT_HAND_DETECTION_CONFIDENCE = 0.5F
        const val DEFAULT_HAND_TRACKING_CONFIDENCE = 0.5F
        const val DEFAULT_HAND_PRESENCE_CONFIDENCE = 0.5F
        const val OTHER_ERROR = 0
        const val GPU_ERROR = 1
    }

    data class ResultBundle(
            val results: List<GestureRecognizerResult>,
            val inferenceTime: Long,
            val inputImageHeight: Int,
            val inputImageWidth: Int,
    )

    interface GestureRecognizerListener {
        fun onError(error: String, errorCode: Int = OTHER_ERROR)
        fun onResults(resultBundle: ResultBundle)
    }
}
