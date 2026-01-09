package com.example.flutoryx_uploader

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.example.flutoryx_uploader.db.UploadDatabase
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.util.concurrent.TimeUnit
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import okhttp3.MediaType
import okhttp3.RequestBody
import okio.BufferedSink
import okio.ForwardingSink
import okio.Sink
import okio.buffer

class DirectUploadWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    private val notificationHelper = NotificationHelper(context)
    private val db = UploadDatabase.getDatabase(context)
    private val dao = db.uploadDao()
    // Using a longer timeout for direct large uploads
    private val client = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(0, TimeUnit.SECONDS) // 0 means no timeout (important for large files)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val taskId = inputData.getString("taskId") ?: return@withContext Result.failure()
        
        Log.d("DirectUploadWorker", "Starting direct upload for taskId: $taskId")
        
        val task = dao.getTask(taskId) ?: return@withContext Result.failure()

        if (task.status == UploadStatus.CANCELED.toResultString()) {
            return@withContext Result.failure()
        }

        if (task.showNotification) {
            setForeground(createForegroundInfo(task.taskId, 0, File(task.filePath).name))
        }

        try {
            dao.updateStatus(taskId, UploadStatus.RUNNING.toResultString())
            
            val file = File(task.filePath)
            if (!file.exists()) {
                Log.e("DirectUploadWorker", "File not found: ${task.filePath}")
                dao.updateStatus(taskId, UploadStatus.FAILED.toResultString())
                if (task.showNotification) notificationHelper.showCompletionNotification(taskId, file.name, false)
                return@withContext Result.failure()
            }

            if (!isNetworkAvailable()) {
                 return@withContext Result.retry()
            }

            // Build Multipart Request
            val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
            
            // Add Fields
            if (task.dataJson != null) {
                val type = object : TypeToken<Map<String, String>>() {}.type
                val dataMap: Map<String, String> = Gson().fromJson(task.dataJson, type)
                for ((k, v) in dataMap) {
                    builder.addFormDataPart(k, v)
                }
            }

            // Add File
            // Note: Content-Type prediction is basic here, could be improved or passed from Dart
            val mediaType = "application/octet-stream".toMediaTypeOrNull()
            builder.addFormDataPart("file", file.name, file.asRequestBody(mediaType))

            val requestBuilder = Request.Builder()
                .url(task.endpoint)
                .post(builder.build())

            // Add Headers
            if (task.headersJson != null) {
                val type = object : TypeToken<Map<String, String>>() {}.type
                val headerMap: Map<String, String> = Gson().fromJson(task.headersJson, type)
                for ((k, v) in headerMap) {
                    requestBuilder.addHeader(k, v)
                }
            }
            
            val request = requestBuilder.build()

            // Execute
            // We use ProgressRequestBody wrapper if we want progress updates during single request?
            // OkHttp doesn't support progress out of the box for request body.
            // But we need notifications!
            // Wait, "Native progress notifications".
            // Direct request in OkHttp: I need a RequestBody that emits progress.
            // Let's implement a CountingRequestBody.
            
            // Re-wrapping the body
            val countingBody = CountingRequestBody(builder.build()) { bytesWritten, contentLength ->
                val progress = ((bytesWritten.toDouble() / contentLength) * 100).toInt()
                // Update DB and Notification occasionally
                if (progress % 5 == 0) { // Limit updates
                     // Update DB less frequently? 
                     // Since doWork is synchronous effectively here (OkHttp call), we need a way to update DB async?
                     // No, callback is on background thread.
                     // IMPORTANT: We cannot update DB too often in a tight loop.
                }
                
                // We should update DB/Notification. To avoid flooding, check time or percent change.
                if (shouldUpdateProgress(taskId, progress)) {
                     updateProgress(taskId, progress, bytesWritten, contentLength, file.name, task.startTime, task.showNotification)
                }
            }
            
            val monitoredRequest = request.newBuilder().post(countingBody).build()
            
            client.newCall(monitoredRequest).execute().use { response ->
                if (response.isSuccessful) {
                    dao.updateStatus(taskId, UploadStatus.COMPLETED.toResultString())
                    dao.updateTaskProgress(taskId, 100, 0.0, 0)
                    if (task.showNotification) notificationHelper.showCompletionNotification(taskId, file.name, true)
                    return@withContext Result.success()
                } else {
                     Log.e("DirectUploadWorker", "Upload failed: ${response.code}")
                     if (response.code in 500..599) return@withContext Result.retry()
                     dao.updateStatus(taskId, UploadStatus.FAILED.toResultString())
                     if (task.showNotification) notificationHelper.showCompletionNotification(taskId, file.name, false)
                     return@withContext Result.failure()
                }
            }

        } catch (e: Exception) {
            e.printStackTrace()
            return@withContext Result.retry()
        }
    }
    
    // Map to track last update time to throttle DB writes
    private val lastUpdateMap = mutableMapOf<String, Long>()
    
    private fun shouldUpdateProgress(taskId: String, progress: Int): Boolean {
         val now = System.currentTimeMillis()
         val last = lastUpdateMap[taskId] ?: 0L
         if (now - last > 500) { // Update every 500ms max
             lastUpdateMap[taskId] = now
             return true
         }
         return false
    }

    private fun updateProgress(taskId: String, progress: Int, bytesWritten: Long, totalBytes: Long, fileName: String, startTime: Long, showNotif: Boolean) {
         val now = System.currentTimeMillis()
         val elapsed = now - startTime
         var speed = 0.0
         var eta: Long? = null
         
         if (elapsed > 1000) {
             speed = (bytesWritten.toDouble() / elapsed) * 1000
             if (speed > 0) {
                 eta = ((totalBytes - bytesWritten) / speed).toLong()
             }
         }
         
         dao.updateTaskProgress(taskId, progress, speed, eta)
         if (showNotif) {
             notificationHelper.updateProgressNotification(taskId, progress, fileName, speed, eta)
         }
    }

    private fun createForegroundInfo(taskId: String, progress: Int, fileName: String, speed: Double = 0.0, eta: Long? = null): ForegroundInfo {
        val notification = notificationHelper.buildProgressNotification(taskId, progress, fileName, speed, eta)
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            return ForegroundInfo(
                taskId.hashCode(), 
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        }
        return ForegroundInfo(taskId.hashCode(), notification)
    }

    private fun isNetworkAvailable(): Boolean {
        val connectivityManager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            val network = connectivityManager.activeNetwork ?: return false
            val activeNetwork = connectivityManager.getNetworkCapabilities(network) ?: return false
            return when {
                activeNetwork.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> true
                activeNetwork.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> true
                activeNetwork.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> true
                else -> false
            }
        } else {
            val networkInfo = connectivityManager.activeNetworkInfo
            return networkInfo != null && networkInfo.isConnected
        }
    }
}

// Helper class for progress monitoring


class CountingRequestBody(
    private val delegate: RequestBody,
    private val onProgress: (Long, Long) -> Unit
) : RequestBody() {
    override fun contentType(): MediaType? = delegate.contentType()
    override fun contentLength(): Long = delegate.contentLength()

    override fun writeTo(sink: BufferedSink) {
        val countingSink = CountingSink(sink)
        val bufferedSink = countingSink.buffer()
        delegate.writeTo(bufferedSink)
        bufferedSink.flush()
    }

    inner class CountingSink(delegate: Sink) : ForwardingSink(delegate) {
        private var bytesWritten = 0L

        override fun write(source: okio.Buffer, byteCount: Long) {
            super.write(source, byteCount)
            bytesWritten += byteCount
            onProgress(bytesWritten, contentLength())
        }
    }
}
