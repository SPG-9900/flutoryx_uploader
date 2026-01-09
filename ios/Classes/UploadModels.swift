import Foundation

enum UploadStatus: String, Codable {
    case enqueued
    case running
    case paused
    case completed
    case failed
    case canceled
}

enum UploadMode: String, Codable {
    case direct
    case chunked
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
    
    var uploadMode: UploadMode = .direct // Default for new tasks
    
    enum CodingKeys: String, CodingKey {
        case taskId, filePath, endpoint, chunkSize, maxParallelUploads, adaptiveNetwork, showNotification, headers, data, status, progress, uploadedChunkIndices, startTime, speed, eta, uploadMode
    }
    
    init(taskId: String, filePath: String, endpoint: String, chunkSize: Int, maxParallelUploads: Int, adaptiveNetwork: Bool, showNotification: Bool, headers: [String: String]?, data: [String: String]?, status: UploadStatus, progress: Int, uploadedChunkIndices: [Int], startTime: Date?, speed: Double, eta: Int?, uploadMode: UploadMode) {
        self.taskId = taskId
        self.filePath = filePath
        self.endpoint = endpoint
        self.chunkSize = chunkSize
        self.maxParallelUploads = maxParallelUploads
        self.adaptiveNetwork = adaptiveNetwork
        self.showNotification = showNotification
        self.headers = headers
        self.data = data
        self.status = status
        self.progress = progress
        self.uploadedChunkIndices = uploadedChunkIndices
        self.startTime = startTime
        self.speed = speed
        self.eta = eta
        self.uploadMode = uploadMode
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try container.decode(String.self, forKey: .taskId)
        filePath = try container.decode(String.self, forKey: .filePath)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        chunkSize = try container.decode(Int.self, forKey: .chunkSize)
        maxParallelUploads = try container.decode(Int.self, forKey: .maxParallelUploads)
        adaptiveNetwork = try container.decode(Bool.self, forKey: .adaptiveNetwork)
        showNotification = try container.decode(Bool.self, forKey: .showNotification)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
        data = try container.decodeIfPresent([String: String].self, forKey: .data)
        status = try container.decode(UploadStatus.self, forKey: .status)
        progress = try container.decode(Int.self, forKey: .progress)
        uploadedChunkIndices = try container.decode([Int].self, forKey: .uploadedChunkIndices)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 0.0
        eta = try container.decodeIfPresent(Int.self, forKey: .eta)
        
        // Backward compatibility: If uploadMode is missing, default to .chunked (since that was the only mode before)
        uploadMode = try container.decodeIfPresent(UploadMode.self, forKey: .uploadMode) ?? .chunked
    }
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
