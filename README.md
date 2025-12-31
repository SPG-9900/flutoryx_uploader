<p align="center">
  <img src="assets/logo.png" width="800" alt="Flutoryx Uploader Logo">
</p>

# Flutoryx Uploader 🚀

A battle-tested Flutter plugin for **resumable, chunked, background-safe file uploads**. 
Designed for high-performance apps that need to handle large file transfers reliably across Android (WorkManager) and iOS (Background URLSession).

<p align="center">
  <a href="https://pub.dev/packages/flutoryx_uploader"><img src="https://img.shields.io/pub/v/flutoryx_uploader" alt="Pub Version"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-purple.svg" alt="License: MIT"></a>
</p>

---

## Why Flutoryx Uploader?

Standard upload plugins often fail when the app is killed or the network blinks. **Flutoryx Uploader** is built as a robust transport engine that treats every file as a series of reliable packets.

### Key Features 🌟
- **📦 Chunked Uploads**: Slices large files into 1MB (configurable) packets.
- **🔄 Smart Resumption**: If a chunk fails at 99%, only that specific 1MB chunk retries, not the whole file. 
- **📈 Real-time Metrics**: Built-in Speed tracking (e.g., `1.4 MB/s`) and ETA estimation (`Remaining: 1m 30s`).
- **🛡️ Resilience**: Automatically reconnects background sessions and resumes tasks after an app kill or device reboot.
- **🔔 Native Feedback**: Integrated Android Foreground Service notifications and iOS local completion alerts.
- **💾 Persistent Queue**: State is managed in native storage (SQLite/Room on Android, JSON on iOS).
- **🕹️ Task Management**: Full control with Pause, Resume, Cancel, and Delete APIs.

---

## Setup 🛠️

### Android
Add these permissions to your `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

### iOS
1. In Xcode, enable **Background fetch** and **Background processing** in "Signing & Capabilities".
2. Add `NSUserNotificationUsageDescription` to your `Info.plist` for upload alerts.

---

## Usage 🚀

### 1. Initialize & Start Upload
```dart
import 'package:flutoryx_uploader/flutoryx_uploader.dart';

final uploader = FlutoryxUploader();

// Single file upload
final taskId = await uploader.uploadFile(
  file: File('/path/to/video.mp4'),
  endpoint: 'https://api.yoursite.com/upload',
  headers: {"Authorization": "Bearer YOUR_TOKEN"},
  config: UploadConfig(
    chunkSize: 1024 * 1024, // 1MB default
    showNotification: true,
  ),
);

// Multiple files (batch)
final taskIds = await uploader.uploadFiles(...);
```

### 2. Listen to Progress (with Speed & ETA)
```dart
uploader.progressStream.listen((event) {
  print('Speed: ${event.speed} B/s');
  print('Remaining: ${event.eta} seconds');
  print('Progress: ${event.progress}%');
});
```

### 3. State Restoration (On App Startup)
```dart
// Fetch all persisted tasks (active, completed, or failed)
final tasks = await uploader.getTasks();
```

---

## Comparison 📊

| Feature | Flutoryx Uploader | standard_uploader |
|---------|-------------------|-------------------|
| Chunked Packets | ✅ (Native Slicing) | ❌ (Raw Multi-part) |
| Speed & ETA | ✅ Built-in | ❌ Manual Logic |
| Resume after Kill | ✅ Native DB Sync | ❌ Often Reset |
| Memory Footprint | 📉 Very Low (1MB/time) | 📈 High (Buffering) |

---

## License 📄
MIT License - Developed with by SPG-9900.
