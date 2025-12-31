package com.example.flutoryx_uploader

enum class UploadStatus {
    ENQUEUED,
    RUNNING,
    PAUSED,
    COMPLETED,
    FAILED,
    CANCELED;

    fun toResultString(): String {
        return name.lowercase()
    }
}
