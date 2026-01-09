import Flutter
import UIKit

public class FlutoryxUploaderPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, FlutterApplicationLifeCycleDelegate {
  
  private var eventSink: FlutterEventSink?
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutoryx_uploader", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "flutoryx_uploader/events", binaryMessenger: registrar.messenger())
    
    let instance = FlutoryxUploaderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
    registrar.addApplicationDelegate(instance)
    
    // Initialize UploadManager to reconnect session and resume tasks
    _ = UploadManager.shared
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "uploadFile":
        handleUploadFile(call, result: result)
    case "uploadFiles":
        handleUploadFiles(call, result: result)
    case "cancelUpload":
        if let args = call.arguments as? [String: Any], let taskId = args["taskId"] as? String {
            PersistenceManager.shared.updateTaskStatus(taskId: taskId, status: .canceled)
            result(nil)
        } else {
             result(FlutterError(code: "INVALID_ARGUMENT", message: "taskId missing", details: nil))
        }
    case "pauseUpload":
         if let args = call.arguments as? [String: Any], let taskId = args["taskId"] as? String {
            PersistenceManager.shared.updateTaskStatus(taskId: taskId, status: .paused)
             // UploadManager logic to pause?
             // Since chunks are atomic, we just stop scheduling next chunk.
            result(nil)
        } else {
             result(FlutterError(code: "INVALID_ARGUMENT", message: "taskId missing", details: nil))
        }
    case "resumeUpload":
          if let args = call.arguments as? [String: Any], let taskId = args["taskId"] as? String {
            UploadManager.shared.startUpload(taskId: taskId)
            result(nil)
             result(FlutterError(code: "INVALID_ARGUMENT", message: "taskId missing", details: nil))
        }
    case "getTasks":
        let tasks = PersistenceManager.shared.getAllTasks()
        let mappedTasks = tasks.map { task -> [String: Any] in
            return [
                "taskId": task.taskId,
                "status": task.status.rawValue.uppercased(),
                "progress": task.progress,
                "speed": task.speed,
                "eta": task.eta ?? NSNull(),
                "errorMessage": NSNull()
            ]
        }
        result(mappedTasks)
    case "removeTask":
        if let args = call.arguments as? [String: Any], let taskId = args["taskId"] as? String {
            UploadManager.shared.cancelUpload(taskId: taskId)
            PersistenceManager.shared.removeTask(taskId: taskId)
            result(nil)
        } else {
             result(FlutterError(code: "INVALID_ARGUMENT", message: "taskId missing", details: nil))
        }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func handleUploadFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      guard let args = call.arguments as? [String: Any],
            let filePath = args["filePath"] as? String,
            let endpoint = args["endpoint"] as? String,
            let config = args["config"] as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing arguments", details: nil))
          return
      }
      
      let taskId = UUID().uuidString
      let chunkSize = config["chunkSize"] as? Int ?? 1024 * 1024
      let maxParallel = config["maxParallelUploads"] as? Int ?? 2
      let adaptive = config["adaptiveNetwork"] as? Bool ?? true
      let showNotification = config["showNotification"] as? Bool ?? true
      let uploadModeStr = config["uploadMode"] as? String ?? "direct"
      let uploadMode = UploadMode(rawValue: uploadModeStr) ?? .direct
      
      let headers = args["headers"] as? [String: String]
      let data = args["data"] as? [String: String]
      
      let task = UploadTask(
        taskId: taskId,
        filePath: filePath,
        endpoint: endpoint,
        chunkSize: chunkSize,
        maxParallelUploads: maxParallel,
        adaptiveNetwork: adaptive,
        showNotification: showNotification,
        headers: headers,
        data: data,
        status: .enqueued,
        progress: 0,
        uploadedChunkIndices: [],
        startTime: Date(),
        speed: 0,
        eta: nil,
        uploadMode: uploadMode
      )
      
      PersistenceManager.shared.addTask(task)
      UploadManager.shared.startUpload(taskId: taskId)
      
      result(taskId)
  }
  
  private func handleUploadFiles(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
       guard let args = call.arguments as? [String: Any],
            let filePaths = args["filePaths"] as? [String],
            let endpoint = args["endpoint"] as? String,
            let config = args["config"] as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing arguments", details: nil))
          return
      }
      
      var taskIds: [String] = []
      
       let chunkSize = config["chunkSize"] as? Int ?? 1024 * 1024
      let maxParallel = config["maxParallelUploads"] as? Int ?? 2
      let adaptive = config["adaptiveNetwork"] as? Bool ?? true
      let showNotification = config["showNotification"] as? Bool ?? true
      let uploadModeStr = config["uploadMode"] as? String ?? "direct"
      let uploadMode = UploadMode(rawValue: uploadModeStr) ?? .direct
      
      let headers = args["headers"] as? [String: String]
      let data = args["data"] as? [String: String]
      
      for path in filePaths {
          let taskId = UUID().uuidString
          taskIds.append(taskId)
          
           let task = UploadTask(
                taskId: taskId,
                filePath: path,
                endpoint: endpoint,
                chunkSize: chunkSize,
                maxParallelUploads: maxParallel,
                adaptiveNetwork: adaptive,
                showNotification: showNotification,
                headers: headers,
                data: data,
                status: .enqueued,
                progress: 0,
                uploadedChunkIndices: [],
                startTime: Date(),
                speed: 0,
                eta: nil,
                uploadMode: uploadMode
              )
           PersistenceManager.shared.addTask(task)
           UploadManager.shared.startUpload(taskId: taskId)
      }
      
      result(taskIds)
  }
    
  // MARK: - Event Channel
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
      self.eventSink = events
      NotificationCenter.default.addObserver(self, selector: #selector(onProgress(_:)), name: NSNotification.Name("FlutoryxProgress"), object: nil)
      return nil
  }
    
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
      self.eventSink = nil
      NotificationCenter.default.removeObserver(self)
      return nil
  }
    
  @objc private func onProgress(_ notification: Notification) {
      guard let userInfo = notification.userInfo, let eventSink = self.eventSink else { return }
      eventSink(userInfo)
  }
    
  // MARK: - Application Delegate
  public func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) -> Bool {
      // Pass completion handler to UploadManager
      // Note: check identifier == "com.flutoryx.uploader.background"
      if identifier == "com.flutoryx.uploader.background" {
          UploadManager.shared.backgroundCompletionHandler = completionHandler
          return true
      }
      return false
  }
}
