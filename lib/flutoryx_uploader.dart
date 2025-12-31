import 'dart:io';

import 'flutoryx_uploader_platform_interface.dart';
import 'src/models.dart';

export 'src/models.dart';

class FlutoryxUploader {
  /// Upload a single file
  Future<String?> uploadFile({
    required File file,
    required String endpoint,
    UploadConfig config = const UploadConfig(),
    Map<String, String>? headers,
    Map<String, String>? data,
  }) {
    return FlutoryxUploaderPlatform.instance.uploadFile(
      filePath: file.absolute.path,
      endpoint: endpoint,
      config: config,
      headers: headers,
      data: data,
    );
  }

  /// Upload multiple files
  Future<List<String>> uploadFiles({
    required List<File> files,
    required String endpoint,
    UploadConfig config = const UploadConfig(),
    Map<String, String>? headers,
    Map<String, String>? data,
  }) {
    return FlutoryxUploaderPlatform.instance.uploadFiles(
      filePaths: files.map((e) => e.absolute.path).toList(),
      endpoint: endpoint,
      config: config,
      headers: headers,
      data: data,
    );
  }

  /// Cancel an upload task
  Future<void> cancelUpload(String taskId) {
    return FlutoryxUploaderPlatform.instance.cancelUpload(taskId);
  }

  /// Pause an upload task
  Future<void> pauseUpload(String taskId) {
    return FlutoryxUploaderPlatform.instance.pauseUpload(taskId);
  }

  /// Resume an upload task
  Future<void> resumeUpload(String taskId) {
    return FlutoryxUploaderPlatform.instance.resumeUpload(taskId);
  }

  /// Retrieves a list of all persisted upload tasks.
  Future<List<UploadProgressEvent>> getTasks() {
    return FlutoryxUploaderPlatform.instance.getTasks();
  }

  /// Removes a task from persistence and cancels it if running.
  Future<void> removeTask(String taskId) {
    return FlutoryxUploaderPlatform.instance.removeTask(taskId);
  }

  /// Stream of progress events
  Stream<UploadProgressEvent> get progressStream {
    return FlutoryxUploaderPlatform.instance.progressStream;
  }
}
