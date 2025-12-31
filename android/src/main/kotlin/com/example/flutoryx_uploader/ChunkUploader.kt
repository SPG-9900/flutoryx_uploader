package com.example.flutoryx_uploader

import com.example.flutoryx_uploader.db.UploadTaskEntity
import com.google.gson.Gson
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.concurrent.TimeUnit
import kotlin.math.min

class ChunkUploader(private val client: OkHttpClient) {

    @Throws(IOException::class)
    fun uploadChunk(
        task: UploadTaskEntity,
        file: File,
        chunkIndex: Int,
        totalChunks: Int,
        uploadedChunks: MutableList<Int>
    ): Int {
        val startOffset = chunkIndex.toLong() * task.chunkSize
        val endOffset = min(startOffset + task.chunkSize, file.length())
        val actualChunkSize = (endOffset - startOffset).toInt()

        if (actualChunkSize <= 0) return 200 // End of file

        val buffer = ByteArray(actualChunkSize)
        RandomAccessFile(file, "r").use { raf ->
            raf.seek(startOffset)
            raf.readFully(buffer)
        }

        val mediaType = "application/octet-stream".toMediaTypeOrNull()
        val requestBody = buffer.toRequestBody(mediaType)

        val multipartBuilder = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("file", file.name, requestBody) // Or "chunk"
            .addFormDataPart("chunkIndex", chunkIndex.toString())
            .addFormDataPart("totalChunks", totalChunks.toString())
            .addFormDataPart("uploadId", task.taskId)
            .addFormDataPart("fileName", file.name)
        
        // Add extra data
        val gson = Gson()
        if (task.dataJson != null) {
            val dataMap = gson.fromJson(task.dataJson, Map::class.java)
            for ((k, v) in dataMap) {
                 multipartBuilder.addFormDataPart(k.toString(), v.toString())
            }
        }

        val requestBuilder = Request.Builder()
            .url(task.endpoint)
            .post(multipartBuilder.build())

        // Add headers
        if (task.headersJson != null) {
            val headersMap = gson.fromJson(task.headersJson, Map::class.java)
            for ((k, v) in headersMap) {
                requestBuilder.addHeader(k.toString(), v.toString())
            }
        }

        val response = client.newCall(requestBuilder.build()).execute()
        val code = response.code
        response.close()
        return code
    }
}
