import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutoryx_uploader/flutoryx_uploader.dart';
import 'package:flutoryx_uploader/flutoryx_uploader_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutoryxUploader platform = MethodChannelFlutoryxUploader();
  const MethodChannel channel = MethodChannel('flutoryx_uploader');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'uploadFile') {
            return 'test_task_id';
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uploadFile', () async {
    final result = await platform.uploadFile(
      filePath: '/tmp/test.txt',
      endpoint: 'https://example.com',
      config: const UploadConfig(),
    );
    expect(result, 'test_task_id');
  });
}
