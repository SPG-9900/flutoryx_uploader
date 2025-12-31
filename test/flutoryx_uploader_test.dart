import 'package:flutter_test/flutter_test.dart';
import 'package:flutoryx_uploader/flutoryx_uploader.dart';
import 'package:flutoryx_uploader/flutoryx_uploader_platform_interface.dart';
import 'package:flutoryx_uploader/flutoryx_uploader_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutoryxUploaderPlatform
    with MockPlatformInterfaceMixin
    implements FlutoryxUploaderPlatform {
  @override
  Future<String?> uploadFile({
    required String filePath,
    required String endpoint,
    required UploadConfig config,
    Map<String, String>? headers,
    Map<String, String>? data,
  }) {
    return Future.value('mock_task_id');
  }

  @override
  Future<List<String>> uploadFiles({
    required List<String> filePaths,
    required String endpoint,
    required UploadConfig config,
    Map<String, String>? headers,
    Map<String, String>? data,
  }) {
    return Future.value(['mock_task_id_1']);
  }

  @override
  Future<void> cancelUpload(String taskId) {
    return Future.value();
  }

  @override
  Future<void> pauseUpload(String taskId) {
    return Future.value();
  }

  @override
  Future<void> resumeUpload(String taskId) {
    return Future.value();
  }

  @override
  Future<List<UploadProgressEvent>> getTasks() {
    return Future.value([]);
  }

  @override
  Future<void> removeTask(String taskId) {
    return Future.value();
  }

  @override
  Stream<UploadProgressEvent> get progressStream => Stream.empty();
}

void main() {
  final FlutoryxUploaderPlatform initialPlatform =
      FlutoryxUploaderPlatform.instance;

  test('$MethodChannelFlutoryxUploader is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutoryxUploader>());
  });

  // Since we don't have a getPlatformVersion anymore, we skip that test or replace it with something generic.
  // The main plugin class just delegates to platform, so we can test that delegation if we want,
  // but simpler to just ensure compilation for now.
}
