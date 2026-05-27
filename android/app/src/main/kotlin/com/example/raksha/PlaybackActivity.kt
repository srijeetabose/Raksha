package com.example.raksha

import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.MediaController
import android.widget.Toast
import android.widget.VideoView
import androidx.appcompat.app.AppCompatActivity
import java.io.File

class PlaybackActivity : AppCompatActivity() {
    
    private var mediaPlayer: MediaPlayer? = null
    private var videoView: VideoView? = null
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val audioPath = intent.getStringExtra("audioPath")
        val videoPath = intent.getStringExtra("videoPath")
        val gesture = intent.getStringExtra("gesture") ?: "Unknown"
        
        Log.d("PlaybackActivity", "� ========== PLAYBACK ACTIVITY ==========")
        Log.d("PlaybackActivity", "Audio path: $audioPath")
        Log.d("PlaybackActivity", "Video path: $videoPath")
        Log.d("PlaybackActivity", "Gesture: $gesture")
        
        // Check which file to play
        val videoFile = if (videoPath != null) File(videoPath) else null
        val audioFile = if (audioPath != null) File(audioPath) else null
        
        Log.d("PlaybackActivity", "Video file exists: ${videoFile?.exists()}")
        Log.d("PlaybackActivity", "Audio file exists: ${audioFile?.exists()}")
        
        when {
            videoFile?.exists() == true -> {
                Log.d("PlaybackActivity", " Playing video: ${videoFile.absolutePath}")
                playVideo(videoFile)
            }
            audioFile?.exists() == true -> {
                Log.d("PlaybackActivity", "� Playing audio: ${audioFile.absolutePath}")
                playAudio(audioFile)
            }
            else -> {
                Log.e("PlaybackActivity", " No valid recording files found")
                Toast.makeText(this, " Recording file not found", Toast.LENGTH_LONG).show()
                finish()
            }
        }
    }
    
    private fun playVideo(videoFile: File) {
        try {
            // Create VideoView programmatically
            videoView = VideoView(this)
            setContentView(videoView)
            
            // Set up media controller
            val mediaController = MediaController(this)
            mediaController.setAnchorView(videoView)
            videoView?.setMediaController(mediaController)
            
            // Set video URI
            videoView?.setVideoURI(Uri.fromFile(videoFile))
            
            // Start playing
            videoView?.setOnPreparedListener { mp ->
                Log.d("PlaybackActivity", " Video prepared, starting playback")
                mp.start()
            }
            
            videoView?.setOnErrorListener { mp, what, extra ->
                Log.e("PlaybackActivity", " Video error: what=$what, extra=$extra")
                Toast.makeText(this, "Error playing video: $what", Toast.LENGTH_LONG).show()
                finish()
                true
            }
            
            videoView?.setOnCompletionListener {
                Log.d("PlaybackActivity", " Video playback completed")
                finish()
            }
            
            Log.d("PlaybackActivity", " Video player initialized")
            
        } catch (e: Exception) {
            Log.e("PlaybackActivity", " Error playing video: ${e.message}")
            e.printStackTrace()
            Toast.makeText(this, "Error: ${e.message}", Toast.LENGTH_LONG).show()
            finish()
        }
    }
    
    private fun playAudio(audioFile: File) {
        try {
            // Create simple UI for audio playback
            val layout = android.widget.LinearLayout(this)
            layout.orientation = android.widget.LinearLayout.VERTICAL
            layout.setPadding(50, 50, 50, 50)
            
            val titleText = android.widget.TextView(this)
            titleText.text = "� Playing Audio Recording"
            titleText.textSize = 20f
            titleText.setPadding(0, 0, 0, 30)
            layout.addView(titleText)
            
            val statusText = android.widget.TextView(this)
            statusText.text = "Loading..."
            statusText.textSize = 16f
            layout.addView(statusText)
            
            val closeButton = android.widget.Button(this)
            closeButton.text = "Close"
            closeButton.setOnClickListener { finish() }
            layout.addView(closeButton)
            
            setContentView(layout)
            
            // Play audio
            mediaPlayer = MediaPlayer().apply {
                setDataSource(audioFile.absolutePath)
                
                setOnPreparedListener {
                    Log.d("PlaybackActivity", " Audio prepared, starting playback")
                    statusText.text = "Playing... Duration: ${duration / 1000}s"
                    start()
                }
                
                setOnCompletionListener {
                    Log.d("PlaybackActivity", " Audio playback completed")
                    statusText.text = "Playback completed"
                    Toast.makeText(this@PlaybackActivity, " Playback completed", Toast.LENGTH_SHORT).show()
                }
                
                setOnErrorListener { mp, what, extra ->
                    Log.e("PlaybackActivity", " Audio error: what=$what, extra=$extra")
                    statusText.text = "Error playing audio"
                    Toast.makeText(this@PlaybackActivity, "Error: $what", Toast.LENGTH_LONG).show()
                    true
                }
                
                prepareAsync()
            }
            
            Log.d("PlaybackActivity", " Audio player initialized")
            
        } catch (e: Exception) {
            Log.e("PlaybackActivity", " Error playing audio: ${e.message}")
            e.printStackTrace()
            Toast.makeText(this, "Error: ${e.message}", Toast.LENGTH_LONG).show()
            finish()
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        mediaPlayer?.release()
        mediaPlayer = null
        videoView = null
        Log.d("PlaybackActivity", " Playback activity destroyed")
    }
}
