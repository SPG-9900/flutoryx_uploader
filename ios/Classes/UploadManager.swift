import UserNotifications

class UploadManager: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    static let shared = UploadManager()
    
    private var session: URLSession!
    private let sessionIdentifier = "com.flutoryx.uploader.background"
    var backgroundCompletionHandler: (() -> Void)?
    
    private let queue = DispatchQueue(label: "com.flutoryx.uploader.queue")
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false // Start immediately if possible
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // Request Notification Permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // Resume pending tasks on app launch
        checkQueue()
    }



    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }



    private func completeTask(taskId: String) {
        PersistenceManager.shared.updateTaskStatus(taskId: taskId, status: .completed)
         NotificationCenter.default.post(name: NSNotification.Name("FlutoryxProgress"), object: nil, userInfo: ["taskId": taskId, "progress": 100, "status": "completed"])
         showNotification(title: "Upload Completed", body: "Task \(taskId.prefix(8)) finished successfully.")
    }
    
    private func failTask(taskId: String, message: String) {
        PersistenceManager.shared.updateTaskStatus(taskId: taskId, status: .failed)
         NotificationCenter.default.post(name: NSNotification.Name("FlutoryxProgress"), object: nil, userInfo: ["taskId": taskId, "progress": 0, "status": "failed", "errorMessage": message])
         showNotification(title: "Upload Failed", body: "Task \(taskId.prefix(8)) failed: \(message)")
    }
    
    func startUpload(taskId: String) {
        PersistenceManager.shared.updateTaskStatus(taskId: taskId, status: .running)
        nextChunk(taskId: taskId)
    }
    
    func cancelUpload(taskId: String) {
        session.getTasksWithCompletionHandler { _, uploads, _ in
            for upload in uploads {
                // Ensure strict match on taskId part of description (taskId|chunkIndex)
                if let description = upload.taskDescription, description.hasPrefix(taskId + "|") {
                    upload.cancel()
                }
            }
        }
    }
    
    func checkQueue() {
        let tasks = PersistenceManager.shared.getAllTasks()
        for task in tasks {
            if task.status == .running {
                // Check if actually running in session?
                // For simplicity, just try to schedule next chunk if not already doing so.
                // In robust app, we reconcile with getTasksWithCompletionHandler
                 session.getTasksWithCompletionHandler { _, uploads, _ in
                     let running = uploads.contains { $0.taskDescription?.starts(with: task.taskId) == true }
                     if !running {
                         self.nextChunk(taskId: task.taskId)
                     }
                 }
            }
        }
    }
    
    private func nextChunk(taskId: String) {
        queue.async {
            guard let task = PersistenceManager.shared.getTask(taskId: taskId) else { return }
            
            if task.status != .running { return }
            
            let fileURL = URL(fileURLWithPath: task.filePath)
            guard let fileSize = try? FileManager.default.attributesOfItem(atPath: task.filePath)[.size] as? Int64 else {
                self.failTask(taskId: taskId, message: "File not found")
                return
            }
            
            // Calc total chunks
            let totalChunks = Int(ceil(Double(fileSize) / Double(task.chunkSize)))
            
            // Find first missing chunk
            var chunkIndexToUpload = -1
            for i in 0..<totalChunks {
                if !task.uploadedChunkIndices.contains(i) {
                    chunkIndexToUpload = i
                    break
                }
            }
            
            if chunkIndexToUpload == -1 {
                // All done
                self.completeTask(taskId: taskId)
                return
            }
            
            // Prepare chunk file
            let startOffset = Int64(chunkIndexToUpload) * Int64(task.chunkSize)
            let endOffset = min(startOffset + Int64(task.chunkSize), fileSize)
            let chunkSize = Int(endOffset - startOffset)
            
            do {
                let fileHandle = try FileHandle(forReadingFrom: fileURL)
                fileHandle.seek(toFileOffset: UInt64(startOffset))
                let data = fileHandle.readData(ofLength: chunkSize)
                fileHandle.closeFile()
                
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("\(taskId)_\(chunkIndexToUpload)")
                try data.write(to: tempFile)
                
                // Create Request
                var request = URLRequest(url: URL(string: task.endpoint)!)
                request.httpMethod = "POST"
                
                // Add headers
                if let headers = task.headers {
                    for (k, v) in headers {
                        request.setValue(v, forHTTPHeaderField: k)
                    }
                }
                
                // Construct multipart in a simpler way or send raw chunk?
                // Specification: "Packet / Chunk-Based Upload".
                // Usually multipart is expected with metadata.
                // Constructing multipart body on disk is hard for background session (need to write whole body to file).
                // Let's create a full multipart body file.
                
                let boundary = "Boundary-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                let bodyFile = tempDir.appendingPathComponent("\(taskId)_\(chunkIndexToUpload)_body")
                var bodyData = Data()
                
                // Add Metadata fields
                func addField(name: String, value: String) {
                    bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
                    bodyData.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                    bodyData.append("\(value)\r\n".data(using: .utf8)!)
                }
                
                addField(name: "chunkIndex", value: "\(chunkIndexToUpload)")
                addField(name: "totalChunks", value: "\(totalChunks)")
                addField(name: "uploadId", value: taskId)
                 addField(name: "fileName", value: fileURL.lastPathComponent)
                
                if let dataMap = task.data {
                    for (k, v) in dataMap {
                        addField(name: k, value: v)
                    }
                }
                
                // File data
                bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
                bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
                bodyData.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                bodyData.append(data) // Append chunk bytes
                bodyData.append("\r\n".data(using: .utf8)!)
                
                bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)
                
                try bodyData.write(to: bodyFile)
                
                // Start Upload
                let uploadTask = self.session.uploadTask(with: request, fromFile: bodyFile)
                uploadTask.taskDescription = "\(taskId)|\(chunkIndexToUpload)"
                uploadTask.resume()
                
                // Cleanup temp files (URLSession copies them? No, for fromFile it reads. 
                // We should delete in delegate didComplete)
                
            } catch {
                self.failTask(taskId: taskId, message: error.localizedDescription)
            }
        }
    }
    
    // MARK: - Delegate Methods
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let description = task.taskDescription else { return }
        let parts = description.split(separator: "|")
        if parts.count != 2 { return }
        
        let taskId = String(parts[0])
        guard let chunkIndex = Int(parts[1]) else { return }
        
        // Remove temp files
        let tempDir = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("\(taskId)_\(chunkIndex)"))
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("\(taskId)_\(chunkIndex)_body"))

        
        if let error = error {
            print("Upload error for \(taskId) chunk \(chunkIndex): \(error)")
            // Retry handling?
            // Exponential backoff could be implemented here. For now, we will retry indefinitely or fail.
            // Let's implement simple retry by rescheduling nextChunk after delay?
            // For background execution, pure delay is tricky.
            // But since session is background, we can just leave it? No, task failed.
            // Let's fail for now to be safe, or just ignore (effectively paused).
            // PersistenceManager.shared.updateTaskStatus(taskId: taskId, status: .failed) 
            // Better: Retry logic.
             DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                self.nextChunk(taskId: taskId)
            }
            return
        }
        
        // Success (check HTTP status code too!)
        if let response = task.response as? HTTPURLResponse, (200...299).contains(response.statusCode) {
             queue.async {
                guard let savedTask = PersistenceManager.shared.getTask(taskId: taskId) else { return }
                var indices = savedTask.uploadedChunkIndices
                if !indices.contains(chunkIndex) {
                    indices.append(chunkIndex)
                }
                
                let fileURL = URL(fileURLWithPath: savedTask.filePath)
                 guard let fileSize = try? FileManager.default.attributesOfItem(atPath: savedTask.filePath)[.size] as? Int64 else { return }
                 let totalChunks = Int(ceil(Double(fileSize) / Double(savedTask.chunkSize)))

                let progress = Int((Double(indices.count) / Double(totalChunks)) * 100)
                
                // Speed & ETA Calculation
                let startTime = savedTask.startTime ?? Date()
                let totalBytesUploaded = Double(indices.count) * Double(savedTask.chunkSize)
                let elapsedSeconds = Date().timeIntervalSince(startTime)
                var speedVal = 0.0
                var etaVal: Int? = nil
                
                if elapsedSeconds > 1 {
                    speedVal = totalBytesUploaded / elapsedSeconds
                    let remainingBytes = Double(fileSize) - totalBytesUploaded
                    if speedVal > 0 {
                        etaVal = Int(remainingBytes / speedVal)
                    }
                }

                PersistenceManager.shared.updateTaskProgress(
                    taskId: taskId, 
                    progress: progress, 
                    uploadedChunkIndices: indices,
                    speed: speedVal,
                    eta: etaVal
                )
                
                 // Fire progress event via Plugin
                 NotificationCenter.default.post(
                    name: NSNotification.Name("FlutoryxProgress"), 
                    object: nil, 
                    userInfo: [
                        "taskId": taskId, 
                        "progress": progress, 
                        "status": "running",
                        "speed": speedVal,
                        "eta": etaVal as Any
                    ]
                 )
                
                // Next
                self.nextChunk(taskId: taskId)
             }
        } else {
            // Server error
             DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                self.nextChunk(taskId: taskId)
            }
        }
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
