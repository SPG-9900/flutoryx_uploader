/// Configuration for file uploads
class UploadConfig {
  /// Size of each chunk in bytes (default 1MB)
  final int chunkSize;

  /// Maximum number of parallel uploads
  final int maxParallelUploads;

  /// Whether to adapt chunk size based on network speed
  final bool adaptiveNetwork;

  /// Retry policy configuration
  final RetryPolicy retryPolicy;

  /// Whether to show a notification during upload (Android)
  final bool showNotification;

  const UploadConfig({
    this.chunkSize = 1024 * 1024, // 1MB
    this.maxParallelUploads = 2,
    this.adaptiveNetwork = true,
    this.retryPolicy = const RetryPolicy(),
    this.showNotification = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'chunkSize': chunkSize,
      'maxParallelUploads': maxParallelUploads,
      'adaptiveNetwork': adaptiveNetwork,
      'retryPolicy': retryPolicy.toMap(),
      'showNotification': showNotification,
    };
  }
}

/// Configuration for retry behavior
class RetryPolicy {
  final int maxRetries;
  final int initialBackoffSeconds;
  final int backoffMultiplier;

  const RetryPolicy({
    this.maxRetries = 3,
    this.initialBackoffSeconds = 2,
    this.backoffMultiplier = 2,
  });

  Map<String, dynamic> toMap() {
    return {
      'maxRetries': maxRetries,
      'initialBackoffSeconds': initialBackoffSeconds,
      'backoffMultiplier': backoffMultiplier,
    };
  }
}

/// Status of an upload task
enum UploadStatus { enqueued, running, paused, completed, failed, canceled }

/// Event emitted during upload progress
class UploadProgressEvent {
  final String taskId;
  final UploadStatus status;
  final int progress; // 0-100
  final String? errorMessage;
  final double speed; // Bytes per second
  final int? eta; // Estimated seconds remaining (null if unknown)

  UploadProgressEvent({
    required this.taskId,
    required this.status,
    required this.progress,
    this.errorMessage,
    this.speed = 0,
    this.eta,
  });

  factory UploadProgressEvent.fromMap(Map<dynamic, dynamic> map) {
    return UploadProgressEvent(
      taskId: map['taskId'] as String,
      status: UploadStatus.values.firstWhere(
        (e) =>
            e.toString().split('.').last ==
            map['status'].toString().toLowerCase(),
        orElse: () => UploadStatus.failed,
      ),
      progress: (map['progress'] as num?)?.toInt() ?? 0,
      errorMessage: map['errorMessage'] as String?,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      eta: (map['eta'] as num?)?.toInt(),
    );
  }
}
