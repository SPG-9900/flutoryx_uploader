import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'flutoryx_uploader_method_channel.dart';
import 'src/models.dart';

abstract class FlutoryxUploaderPlatform extends PlatformInterface {
  /// Constructs a FlutoryxUploaderPlatform.
  FlutoryxUploaderPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutoryxUploaderPlatform _instance = MethodChannelFlutoryxUploader();

  /// The default instance of [FlutoryxUploaderPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutoryxUploader].
  static FlutoryxUploaderPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutoryxUploaderPlatform] when
  /// they register themselves.
  static set instance(FlutoryxUploaderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> uploadFile({
    required String filePath,
    required String endpoint,
    required UploadConfig config,
    Map<String, String>? headers,
    Map<String, String>? data,
  }) {
    throw UnimplementedError('uploadFile() has not been implemented.');
  }

  Future<List<String>> uploadFiles({
    required List<String> filePaths,
    required String endpoint,
    required UploadConfig config,
    Map<String, String>? headers,
    Map<String, String>? data,
  }) {
    throw UnimplementedError('uploadFiles() has not been implemented.');
  }

  Future<void> cancelUpload(String taskId) {
    throw UnimplementedError('cancelUpload() has not been implemented.');
  }

  Future<void> pauseUpload(String taskId) {
    throw UnimplementedError('pauseUpload() has not been implemented.');
  }

  Future<void> resumeUpload(String taskId) {
    throw UnimplementedError('resumeUpload() has not been implemented.');
  }

  /// Retrieves a list of all persisted upload tasks.
  Future<List<UploadProgressEvent>> getTasks() {
    throw UnimplementedError('getTasks() has not been implemented.');
  }

  /// Removes a task from persistence and cancels it if running.
  Future<void> removeTask(String taskId) {
    throw UnimplementedError('removeTask() has not been implemented.');
  }

  Stream<UploadProgressEvent> get progressStream {
    throw UnimplementedError('progressStream has not been implemented.');
  }
}
