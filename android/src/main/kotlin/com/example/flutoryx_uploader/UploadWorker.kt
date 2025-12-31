package com.example.flutoryx_uploader

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.example.flutoryx_uploader.db.UploadDatabase
import com.example.flutoryx_uploader.db.UploadTaskEntity
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import java.io.File
import kotlin.math.ceil
import java.util.concurrent.TimeUnit
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

class UploadWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    private val notificationHelper = NotificationHelper(context)
    private val db = UploadDatabase.getDatabase(context)
    private val dao = db.uploadDao()
    private val chunkUploader = ChunkUploader(OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build())

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val taskId = inputData.getString("taskId") ?: return@withContext Result.failure()
        
        Log.d("UploadWorker", "Starting work for taskId: $taskId")
        
        val task = dao.getTask(taskId) ?: return@withContext Result.failure()

        if (task.status == UploadStatus.CANCELED.toResultString()) {
            return@withContext Result.failure()
        }

        if (task.showNotification) {
            setForeground(createForegroundInfo(task.taskId, task.progress, File(task.filePath).name))
        }

        try {
            dao.updateStatus(taskId, UploadStatus.RUNNING.toResultString())
            
            val file = File(task.filePath)
            if (!file.exists()) {
                Log.e("UploadWorker", "File not found: ${task.filePath}")
                dao.updateStatus(taskId, UploadStatus.FAILED.toResultString())
                if (task.showNotification) notificationHelper.showCompletionNotification(taskId, file.name, false)
                return@withContext Result.failure()
            }

            val totalSize = file.length()
            val totalChunks = ceil(totalSize.toDouble() / task.chunkSize).toInt()
            
            val uploadedChunksType = object : TypeToken<MutableList<Int>>() {}.type
            val uploadedChunks: MutableList<Int> = Gson().fromJson(task.uploadedChunksJson, uploadedChunksType)

            // Re-check status before loop
            if (dao.getTask(taskId)?.status == UploadStatus.CANCELED.toResultString()) return@withContext Result.failure()

            for (i in 0 until totalChunks) {
                if (uploadedChunks.contains(i)) continue

                if (isStopped) { // Worker stopped by OS or cancelWork
                     dao.updateStatus(taskId, UploadStatus.PAUSED.toResultString())
                     return@withContext Result.retry()
                }
                
                // Refetch task to check for user pause/cancel
                val currentTask = dao.getTask(taskId)
                if (currentTask?.status == UploadStatus.PAUSED.toResultString()) return@withContext Result.retry()
                if (currentTask?.status == UploadStatus.CANCELED.toResultString()) return@withContext Result.failure()

                // Check connectivity before attempting upload
                if (!isNetworkAvailable()) {
                    Log.d("UploadWorker", "No network availble, retrying...")
                    // Optionally update notification to "Waiting for network..."
                    return@withContext Result.retry()
                }

                val statusCode = try {
                     chunkUploader.uploadChunk(task, file, i, totalChunks, uploadedChunks)
                } catch (e: Exception) {
                    Log.e("UploadWorker", "Exception during uploadChunk: ${e.message}")
                    // Network error or timeout -> Retry
                    return@withContext Result.retry()
                }
                
                if (statusCode in 200..299) {
                    uploadedChunks.add(i)
                    val progress = ((uploadedChunks.size.toDouble() / totalChunks) * 100).toInt()
                    
                    // Refetch task to avoid overwriting status changes and get correct startTime
                    val taskToUpdate = dao.getTask(taskId) ?: task
                    
                    // Speed & ETA Calculation
                    val taskStartTime = if (taskToUpdate.startTime > 0) taskToUpdate.startTime else System.currentTimeMillis()
                    val totalBytesUploaded = uploadedChunks.size.toLong() * taskToUpdate.chunkSize
                    val elapsedMillis = System.currentTimeMillis() - taskStartTime
                    var speedVal = 0.0
                    var etaVal: Long? = null
                    
                    if (elapsedMillis > 1000) {
                        speedVal = (totalBytesUploaded.toDouble() / elapsedMillis) * 1000
                        val remainingBytes = totalSize - totalBytesUploaded
                        if (speedVal > 0) {
                            etaVal = (remainingBytes / speedVal).toLong()
                        }
                    }

                    val updatedTask = taskToUpdate.copy(
                        uploadedChunksJson = Gson().toJson(uploadedChunks),
                        progress = progress,
                        status = UploadStatus.RUNNING.toResultString(),
                        speed = speedVal,
                        eta = etaVal
                    )
                    dao.update(updatedTask)
                    
                    if (taskToUpdate.showNotification) {
                        setForeground(createForegroundInfo(taskId, progress, file.name, speedVal, etaVal))
                    }
                } else if (statusCode in 400..499) {
                    // Fatal client error
                    Log.e("UploadWorker", "Fatal error $statusCode. Stopping.")
                    dao.updateStatus(taskId, UploadStatus.FAILED.toResultString())
                    if (task.showNotification) notificationHelper.showCompletionNotification(taskId, file.name, false)
                    return@withContext Result.failure()
                } else {
                    // Server error (5xx) -> Retry
                    Log.w("UploadWorker", "Server error $statusCode. Retrying.")
                    return@withContext Result.retry()
                }
            }

            dao.updateStatus(taskId, UploadStatus.COMPLETED.toResultString())
            if (task.showNotification) notificationHelper.showCompletionNotification(taskId, file.name, true)
            
            return@withContext Result.success()

        } catch (e: Exception) {
            e.printStackTrace()
             Log.e("UploadWorker", "Unexpected error: ${e.message}")
            // dao.updateStatus(taskId, UploadStatus.FAILED.toResultString()) 
            // Better to let WorkManager retry
            return@withContext Result.retry()
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
