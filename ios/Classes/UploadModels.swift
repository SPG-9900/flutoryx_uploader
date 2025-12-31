import Foundation

enum UploadStatus: String, Codable {
    case enqueued
    case running
    case paused
    case completed
    case failed
    case canceled
}

struct UploadTask: Codable, Equatable {
    let taskId: String
    let filePath: String
    let endpoint: String
    let chunkSize: Int
    let maxParallelUploads: Int
    let adaptiveNetwork: Bool
    let showNotification: Bool
    let headers: [String: String]?
    let data: [String: String]?
    
    var status: UploadStatus
    var progress: Int
    var uploadedChunkIndices: [Int]
    
    var startTime: Date?
    var speed: Double = 0.0
    var eta: Int?
}

class PersistenceManager {
    static let shared = PersistenceManager()
    private let fileName = "flutoryx_upload_tasks.json"
    private var tasks: [UploadTask] = []
    private let queue = DispatchQueue(label: "com.flutoryx.persistence")
    
    init() {
        loadTasks()
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0]
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private func loadTasks() {
        let url = getDocumentsDirectory().appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            if let loaded = try? decoder.decode([UploadTask].self, from: data) {
                tasks = loaded
            }
        }
    }
    
    func saveTasks() {
        queue.async {
            let url = self.getDocumentsDirectory().appendingPathComponent(self.fileName)
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(self.tasks) {
                try? data.write(to: url)
            }
        }
    }
    
    func addTask(_ task: UploadTask) {
        tasks.append(task)
        saveTasks()
    }
    
    func updateTask(_ task: UploadTask) {
        if let index = tasks.firstIndex(where: { $0.taskId == task.taskId }) {
            tasks[index] = task
            saveTasks()
        }
    }
    
    func getTask(taskId: String) -> UploadTask? {
        return tasks.first(where: { $0.taskId == taskId })
    }
    
    func getAllTasks() -> [UploadTask] {
        return tasks
    }
    
    func removeTask(taskId: String) {
        tasks.removeAll(where: { $0.taskId == taskId })
        saveTasks()
    }
    
    func updateTaskStatus(taskId: String, status: UploadStatus) {
        if var task = getTask(taskId: taskId) {
            task.status = status
            updateTask(task)
        }
    }
    
    func updateTaskProgress(taskId: String, progress: Int, uploadedChunkIndices: [Int], speed: Double = 0, eta: Int? = nil) {
        if var task = getTask(taskId: taskId) {
            task.progress = progress
            task.uploadedChunkIndices = uploadedChunkIndices
            task.speed = speed
            task.eta = eta
            updateTask(task)
        }
    }
}
