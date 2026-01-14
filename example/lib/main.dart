import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutoryx_uploader/flutoryx_uploader.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutoryx Uploader',
      theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true),
      home: const UploadScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home Screen')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home, size: 100, color: Colors.deepPurple),
            const SizedBox(height: 20),
            const Text(
              'Welcome to Flutoryx Uploader!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Manage your background uploads efficiently.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Uploads'),
            ),
          ],
        ),
      ),
    );
  }
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _flutoryxUploader = FlutoryxUploader();
  final List<UploadItem> _uploads = [];
  StreamSubscription? _progressSubscription;
  bool _useChunkedUpload = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadPersistedTasks();
    _progressSubscription = _flutoryxUploader.progressStream.listen((event) {
      if (!mounted) return;
      setState(() {
        final index = _uploads.indexWhere((u) => u.taskId == event.taskId);
        if (index != -1) {
          _uploads[index] = _uploads[index].copyWith(
            status: event.status,
            progress: event.progress,
            errorMessage: event.errorMessage,
            speed: event.speed,
            eta: event.eta,
          );
        } else {
          _uploads.add(
            UploadItem(
              taskId: event.taskId,
              fileName: "Restored Task",
              status: event.status,
              progress: event.progress,
              errorMessage: event.errorMessage,
              speed: event.speed,
              eta: event.eta,
            ),
          );
        }
      });
    });
  }

  Future<void> _loadPersistedTasks() async {
    try {
      final tasks = await _flutoryxUploader.getTasks();
      if (!mounted) return;

      setState(() {
        _uploads.clear();
        for (final task in tasks) {
          _uploads.add(
            UploadItem(
              taskId: task.taskId,
              fileName: "Task ${task.taskId.substring(0, 8)}...",
              status: task.status,
              progress: task.progress,
              errorMessage: task.errorMessage,
              speed: task.speed,
              eta: task.eta,
            ),
          );
        }
      });
    } catch (e) {
      debugPrint("Failed to load tasks: $e");
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.storage, Permission.notification].request();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null) {
      final uploadMode = _useChunkedUpload
          ? UploadMode.chunked
          : UploadMode.direct;
      final config = UploadConfig(
        chunkSize: 512 * 1024,
        showNotification: true,
        uploadMode: uploadMode,
      );

      if (result.paths.length == 1) {
        final file = File(result.paths.first!);
        final taskId = await _flutoryxUploader.uploadFile(
          file: file,
          endpoint: "https://httpbin.org/post", // Example endpoint
          config: config,
          data: {"userId": "123"},
        );

        if (taskId != null) {
          setState(() {
            _uploads.add(
              UploadItem(
                taskId: taskId,
                fileName: file.path.split('/').last,
                status: UploadStatus.enqueued,
                progress: 0,
              ),
            );
          });
        }
      } else {
        final files = result.paths.map((p) => File(p!)).toList();
        final taskIds = await _flutoryxUploader.uploadFiles(
          files: files,
          endpoint: "https://httpbin.org/post",
          config: config,
        );

        setState(() {
          for (int i = 0; i < files.length; i++) {
            _uploads.add(
              UploadItem(
                taskId: taskIds[i],
                fileName: files[i].path.split('/').last,
                status: UploadStatus.enqueued,
                progress: 0,
              ),
            );
          }
        });
      }
    }
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return "${bytesPerSecond.toStringAsFixed(1)} B/s";
    }
    if (bytesPerSecond < 1024 * 1024) {
      return "${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s";
    }
    return "${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return "${seconds}s";
    if (seconds < 3600) {
      return "${seconds ~/ 60}m ${seconds % 60}s";
    }
    return "${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutoryx Uploader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
              );
            },
            tooltip: 'Go to Home Screen',
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('Use Chunked Upload'),
            value: _useChunkedUpload,
            onChanged: (bool value) {
              setState(() {
                _useChunkedUpload = value;
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Select Files & Upload'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _uploads.length,
              itemBuilder: (context, index) {
                final item = _uploads[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: Text(item.fileName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: item.progress / 100),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${item.status.name.toUpperCase()} - ${item.progress}%',
                            ),
                            if (item.status == UploadStatus.running &&
                                item.speed > 0)
                              Text(_formatSpeed(item.speed)),
                          ],
                        ),
                        if (item.status == UploadStatus.running &&
                            item.eta != null)
                          Text(
                            'Remaining: ${_formatDuration(item.eta!)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (item.errorMessage != null)
                          Text(
                            item.errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.status == UploadStatus.running ||
                            item.status == UploadStatus.enqueued)
                          IconButton(
                            icon: const Icon(Icons.pause),
                            onPressed: () =>
                                _flutoryxUploader.pauseUpload(item.taskId),
                          ),
                        if (item.status == UploadStatus.paused ||
                            item.status == UploadStatus.failed)
                          IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () =>
                                _flutoryxUploader.resumeUpload(item.taskId),
                          ),
                        // IconButton(
                        //   icon: const Icon(Icons.cancel),
                        //   onPressed: () =>
                        //       _flutoryxUploader.cancelUpload(item.taskId),
                        // ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await _flutoryxUploader.removeTask(item.taskId);
                            if (context.mounted) {
                              setState(() {
                                _uploads.removeWhere(
                                  (u) => u.taskId == item.taskId,
                                );
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Task deleted')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class UploadItem {
  final String taskId;
  final String fileName;
  final UploadStatus status;
  final int progress;
  final String? errorMessage;
  final double speed;
  final int? eta;

  UploadItem({
    required this.taskId,
    required this.fileName,
    required this.status,
    required this.progress,
    this.errorMessage,
    this.speed = 0,
    this.eta,
  });

  UploadItem copyWith({
    String? taskId,
    String? fileName,
    UploadStatus? status,
    int? progress,
    String? errorMessage,
    double? speed,
    int? eta,
  }) {
    return UploadItem(
      taskId: taskId ?? this.taskId,
      fileName: fileName ?? this.fileName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
    );
  }
}
