package com.example.flutoryx_uploader

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import androidx.work.WorkInfo
import com.example.flutoryx_uploader.db.UploadDatabase
import com.example.flutoryx_uploader.db.UploadTaskEntity
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import java.util.concurrent.TimeUnit

/** FlutoryxUploaderPlugin */
class FlutoryxUploaderPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  private lateinit var channel : MethodChannel
  private lateinit var eventChannel: EventChannel
  private lateinit var context: Context
  private lateinit var db: UploadDatabase
  private lateinit var workManager: WorkManager
  private val mainScope = CoroutineScope(Dispatchers.Main)
  private var eventSink: EventChannel.EventSink? = null
  private var progressJob: Job? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutoryx_uploader")
    channel.setMethodCallHandler(this)
    
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutoryx_uploader/events")
    eventChannel.setStreamHandler(this)

    db = UploadDatabase.getDatabase(context)
    workManager = WorkManager.getInstance(context)
  
    startProgressWatcher()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "uploadFile" -> {
        val taskId = UUID.randomUUID().toString()
        handleUploadFile(call, result, taskId)
        result.success(taskId)
      }
      "uploadFiles" -> {
        handleUploadFiles(call, result)
      }
      "cancelUpload" -> {
        val taskId = call.argument<String>("taskId")
        if (taskId != null) {
          mainScope.launch {
            cancelUpload(taskId)
            result.success(null)
          }
        } else {
          result.error("INVALID_ARGUMENT", "taskId is null", null)
        }
      }
      "pauseUpload" -> {
          val taskId = call.argument<String>("taskId")
           if (taskId != null) {
               mainScope.launch {
                   pauseUpload(taskId)
                   result.success(null)
               }
           } else {
               result.error("INVALID_ARGUMENT", "taskId is null", null)
           }
      }
      "resumeUpload" -> {
          val taskId = call.argument<String>("taskId")
          if (taskId != null) {
              mainScope.launch {
                  resumeUpload(taskId)
                   result.success(null)
              }
          } else {
              result.error("INVALID_ARGUMENT", "taskId is null", null)
          }
      }
      "getTasks" -> {
          mainScope.launch {
              val tasks = withContext(Dispatchers.IO) {
                  db.uploadDao().getAllTasks()
              }
              val mappedTasks = tasks.map { task ->
                  mapOf(
                      "taskId" to task.taskId,
                      "status" to task.status,
                      "progress" to task.progress,
                      "speed" to task.speed,
                      "eta" to task.eta,
                      "errorMessage" to null // TODO: Add error column to DB
                  )
              }
              result.success(mappedTasks)
          }
      }
      "removeTask" -> {
          val taskId = call.argument<String>("taskId")
          if (taskId != null) {
              mainScope.launch {
                  // Cancel WorkManager task by Unique Name (which is the taskId)
                  workManager.cancelUniqueWork(taskId)
                  
                  // Delete from DB
                   withContext(Dispatchers.IO) {
                       db.uploadDao().delete(taskId)
                   }
                  result.success(null)
              }
          } else {
              result.error("INVALID_ARGUMENT", "taskId is null", null)
          }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  private fun handleUploadFile(call: MethodCall, result: Result?, taskId: String) {
    val filePath = call.argument<String>("filePath")!!
    val endpoint = call.argument<String>("endpoint")!!
    val configMap = call.argument<Map<String, Any>>("config")!!
    val headers = call.argument<Map<String, String>>("headers")
    val data = call.argument<Map<String, String>>("data")

    val gson = Gson()
    val headersJson = if (headers != null) gson.toJson(headers) else null
    val dataJson = if (data != null) gson.toJson(data) else null

    val chunkSize = (configMap["chunkSize"] as? Number)?.toInt() ?: 1024 * 1024
    val maxParallelUploads = (configMap["maxParallelUploads"] as? Number)?.toInt() ?: 2
    val adaptiveNetwork = configMap["adaptiveNetwork"] as? Boolean ?: true
    val showNotification = configMap["showNotification"] as? Boolean ?: true
    val uploadMode = configMap["uploadMode"] as? String ?: "direct" // Default to direct
    
    // retry logic extraction...

    val taskEntity = UploadTaskEntity(
      taskId = taskId,
      filePath = filePath,
      endpoint = endpoint,
      chunkSize = chunkSize,
      maxParallelUploads = maxParallelUploads,
      adaptiveNetwork = adaptiveNetwork,
      maxRetries = 3, // TODO: extract from config
      status = UploadStatus.ENQUEUED.toResultString(),
      showNotification = showNotification,
      startTime = System.currentTimeMillis(),
      headersJson = headersJson,
      dataJson = dataJson,
      uploadMode = uploadMode
    )

    mainScope.launch {
       withContext(Dispatchers.IO) {
           db.uploadDao().insert(taskEntity)
       }
       enqueueWork(taskId, adaptiveNetwork, uploadMode)
    }
  }
  
  private fun handleUploadFiles(call: MethodCall, result: Result) {
      val filePaths = call.argument<List<String>>("filePaths")!!
      val endpoint = call.argument<String>("endpoint")!!
      // reuse same config for all
      
      val taskIds = mutableListOf<String>()
      
      filePaths.forEach { path ->
          val taskId = UUID.randomUUID().toString()
          taskIds.add(taskId)
          
          // Re-create arguments for this specific file
          val singleFileArgs = HashMap(call.arguments as Map<String, Any>)
          singleFileArgs["filePath"] = path
          
          val methodCall = MethodCall("uploadFile", singleFileArgs)
          handleUploadFile(methodCall, null, taskId)
      }
      result.success(taskIds)
  }

  private fun enqueueWork(taskId: String, adaptiveNetwork: Boolean, uploadMode: String) {
      val constraints = Constraints.Builder()
          .setRequiredNetworkType(NetworkType.CONNECTED)
          .build()

      val data = Data.Builder()
          .putString("taskId", taskId)
          .build()

      val workerClass = if (uploadMode == "chunked") UploadWorker::class.java else DirectUploadWorker::class.java

      val request = OneTimeWorkRequest.Builder(workerClass)
          .setConstraints(constraints)
          .setInputData(data)
          .addTag(taskId)
          .setBackoffCriteria(BackoffPolicy.LINEAR, 10, TimeUnit.SECONDS)
          .build()

      workManager.enqueueUniqueWork(taskId, ExistingWorkPolicy.REPLACE, request)
  }
  
  private suspend fun cancelUpload(taskId: String) {
      workManager.cancelUniqueWork(taskId)
      withContext(Dispatchers.IO) {
          db.uploadDao().updateStatus(taskId, UploadStatus.CANCELED.toResultString())
      }
  }

    private suspend fun pauseUpload(taskId: String) {
        workManager.cancelUniqueWork(taskId) // Cancels current worker
        withContext(Dispatchers.IO) {
            db.uploadDao().updateStatus(taskId, UploadStatus.PAUSED.toResultString())
        }
    }
    
    private suspend fun resumeUpload(taskId: String) {
          withContext(Dispatchers.IO) {
            val task = db.uploadDao().getTask(taskId)
            if (task != null) {
                db.uploadDao().updateStatus(taskId, UploadStatus.ENQUEUED.toResultString())
                enqueueWork(taskId, task.adaptiveNetwork, task.uploadMode)
            }
        }
    }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    progressJob?.cancel()
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }
  
  // Polling DB for progress updates. 
  // Ideally we use Room's Flow or LiveData, but we need to pipe it to EventChannel.
  // A simple poller is easiest for now to avoid extensive boilerplate with Flows -> EventChannel.
  private fun startProgressWatcher() {
      progressJob = mainScope.launch {
          while (isActive) {
              val tasks = withContext(Dispatchers.IO) {
                  db.uploadDao().getAllPendingTasks() // Maybe get all active tasks
              }
              // Actually we want ALL tasks that might have updates.
              // For efficiency, maybe only grab RUNNING ones or ones updated recently.
              // But simpler: just grab all RUNNING/ENQUEUED/FAILED/COMPLETED that changed?
              // Let's just grab active tasks.
              
              // To properly stream 'progress', we need to check ALL tasks that are relevant. 
              // But iterating whole DB is bad.
              // Let's rely on the Worker updating the DB, and we only poll tasks that are NOT in a final state?
              // Or user specifically subscribes to ID? The API is a global stream.
              
              // Let's polling active tasks.
               val activeTasks = withContext(Dispatchers.IO) {
                  // Query is predefined in DAO: "SELECT * FROM upload_tasks WHERE status = 'ENQUEUED' OR status = 'RUNNING'"
                  // Add PAUSED?
                  db.uploadDao().getAllTasks()
                }
               
               for (task in activeTasks) {
                   val event = mapOf(
                       "taskId" to task.taskId,
                       "status" to task.status,
                       "progress" to task.progress,
                       "speed" to task.speed,
                       "eta" to task.eta,
                       "errorMessage" to null // TODO store error message
                   )
                   eventSink?.success(event)
               }
               
              delay(500) // 500ms poll
          }
      }
  }
}
