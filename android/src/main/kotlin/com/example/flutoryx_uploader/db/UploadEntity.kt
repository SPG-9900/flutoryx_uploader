package com.example.flutoryx_uploader.db

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.example.flutoryx_uploader.UploadStatus

@Entity(tableName = "upload_tasks")
data class UploadTaskEntity(
    @PrimaryKey
    val taskId: String,
    val filePath: String,
    val endpoint: String,
    val chunkSize: Int,
    val maxParallelUploads: Int,
    val adaptiveNetwork: Boolean,
    val maxRetries: Int,
    val currentRetryCount: Int = 0,
    val status: String,
    val progress: Int = 0,
    val uploadedChunksJson: String = "[]", // JSON string of list of uploaded chunk indexes
    val showNotification: Boolean = true,
    val startTime: Long = 0,
    val speed: Double = 0.0,
    val eta: Long? = null,
    val headersJson: String? = null,
    val dataJson: String? = null,
    val uploadMode: String = "direct"
)
