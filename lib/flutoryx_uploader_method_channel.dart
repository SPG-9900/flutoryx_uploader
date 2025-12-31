import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutoryx_uploader_platform_interface.dart';
import 'src/models.dart';

/// An implementation of [FlutoryxUploaderPlatform] that uses method channels.
class MethodChannelFlutoryxUploader extends FlutoryxUploaderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutoryx_uploader');

  @visibleForTesting
  final eventChannel = const EventChannel('flutoryx_uploader/events');

  Stream<UploadProgressEvent>? _progressStream;

  @override
  Future<String?> uploadFile({
    required String filePath,
    required String endpoint,
    required UploadConfig config,
    Map<String, String>? headers,
    Map<String, String>? data,
  }) async {
    final taskId = await methodChannel.invokeMethod<String>('uploadFile', {
      'filePath': filePath,
      'endpoint': endpoint,
      'config': config.toMap(),
      'headers': headers,
      'data': data,
    });
    return taskId;
  }

  @override
  Future<List<String>> uploadFiles({
    required List<String> filePaths,
    required String endpoint,
    required UploadConfig config,
    Map<String, String>? headers,
    Map<String, String>? data,
  }) async {
    final result = await methodChannel.invokeListMethod<String>('uploadFiles', {
      'filePaths': filePaths,
      'endpoint': endpoint,
      'config': config.toMap(),
      'headers': headers,
      'data': data,
    });
    return result ?? [];
  }

  @override
  Future<void> cancelUpload(String taskId) async {
    await methodChannel.invokeMethod('cancelUpload', {'taskId': taskId});
  }

  @override
  Future<void> pauseUpload(String taskId) async {
    await methodChannel.invokeMethod('pauseUpload', {'taskId': taskId});
  }

  @override
  Future<void> resumeUpload(String taskId) async {
    await methodChannel.invokeMethod('resumeUpload', {'taskId': taskId});
  }

  @override
  Future<List<UploadProgressEvent>> getTasks() async {
    final List<dynamic>? tasks = await methodChannel.invokeListMethod<dynamic>(
      'getTasks',
    );
    if (tasks == null) return [];

    return tasks.map((task) {
      final map = Map<String, dynamic>.from(task);
      return UploadProgressEvent(
        taskId: map['taskId'] as String,
        status: _parseStatus(map['status'] as String),
        progress: (map['progress'] as num).toInt(),
        errorMessage: map['errorMessage'] as String?,
      );
    }).toList();
  }

  @override
  Future<void> removeTask(String taskId) async {
    await methodChannel.invokeMethod<void>('removeTask', {'taskId': taskId});
  }

  UploadStatus _parseStatus(String status) {
    switch (status) {
      case 'ENQUEUED':
        return UploadStatus.enqueued;
      case 'RUNNING':
        return UploadStatus.running;
      case 'PAUSED':
        return UploadStatus.paused;
      case 'COMPLETED':
        return UploadStatus.completed;
      case 'FAILED':
        return UploadStatus.failed;
      case 'CANCELED':
        return UploadStatus.canceled;
      default:
        return UploadStatus.failed;
    }
  }

  @override
  Stream<UploadProgressEvent> get progressStream {
    _progressStream ??= eventChannel.receiveBroadcastStream().map((event) {
      return UploadProgressEvent.fromMap(event as Map);
    });
    return _progressStream!;
  }
}
