package com.example.flutoryx_uploader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class NotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "flutoryx_upload_channel"
        const val CHANNEL_NAME = "File Uploads"
        const val NOTIFICATION_ID_BASE = 1000
    }

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress of file uploads"
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    fun buildProgressNotification(taskId: String, progress: Int, fileName: String, speed: Double = 0.0, eta: Long? = null): Notification {
        // Intent to open the app when tapped
        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = if (openAppIntent != null) {
            PendingIntent.getActivity(
                context, 
                0, 
                openAppIntent, 
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            )
        } else {
            null
        }

        val speedText = if (speed > 0) " • ${_formatSpeed(speed)}" else ""
        val etaText = if (eta != null) "\nRemaining: ${_formatDuration(eta)}" else ""

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("Uploading $fileName")
            .setContentText("$progress%$speedText$etaText")
            .setProgress(100, progress, false)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$progress%$speedText$etaText"))
            .build()
    }

    private fun _formatSpeed(bytesPerSecond: Double): String {
        return when {
            bytesPerSecond < 1024 -> "%.1f B/s".format(bytesPerSecond)
            bytesPerSecond < 1024 * 1024 -> "%.1f KB/s".format(bytesPerSecond / 1024)
            else -> "%.1f MB/s".format(bytesPerSecond / (1024 * 1024))
        }
    }

    private fun _formatDuration(seconds: Long): String {
        return when {
            seconds < 60 -> "${seconds}s"
            seconds < 3600 -> "${seconds / 60}m ${seconds % 60}s"
            else -> "${seconds / 3600}h ${(seconds % 3600) / 60}m"
        }
    }
    
    fun showCompletionNotification(taskId: String, fileName: String, success: Boolean) {
        val notificationId = taskId.hashCode()
        val title = if (success) "Upload Complete" else "Upload Failed"
        val message = if (success) "$fileName uploaded successfully" else "Failed to upload $fileName"
        
         val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(if (success) android.R.drawable.stat_sys_upload_done else android.R.drawable.stat_notify_error)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
            
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, notification)
    }
}
