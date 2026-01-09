## 1.1.0
* **New Feature**: Added `UploadMode` support.
  * `UploadMode.direct` (Default): Standard multipart/form-data upload.
  * `UploadMode.chunked`: Resumable, chunked upload.
* Added `DirectUploadWorker` for Android with native progress notifications.
* Added `startDirectUpload` for iOS with background URLSession support.
* **Breaking Change**: Default upload mode is now `Direct` instead of Chunked.

## 1.0.1

* Documentation update: Clarified comparison table in README.md.

## 1.0.0

* Initial release of the Flutoryx Uploader plugin.
* High-performance chunked upload engine (1MB default packets).
* Background support for Android (WorkManager) and iOS (Background URLSession).
* Real-time Speed Tracking (KB/s, MB/s) and ETA Estimation.
* Native persistence (Room on Android, JSON on iOS) surviving app kills/restarts.
* Advanced task management: Pause, Resume, Cancel, and Delete.
* Native progress notifications on Android and completion alerts on iOS.
