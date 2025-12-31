package com.example.flutoryx_uploader.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update

@Dao
interface UploadDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun insert(task: UploadTaskEntity)

    @Update
    fun update(task: UploadTaskEntity)

    @Query("SELECT * FROM upload_tasks WHERE taskId = :taskId")
    fun getTask(taskId: String): UploadTaskEntity?

    @Query("SELECT * FROM upload_tasks WHERE status = 'ENQUEUED' OR status = 'RUNNING'")
    fun getAllPendingTasks(): List<UploadTaskEntity>

    @Query("SELECT * FROM upload_tasks")
    fun getAllTasks(): List<UploadTaskEntity>
    
    @Query("UPDATE upload_tasks SET status = :status WHERE taskId = :taskId")
    fun updateStatus(taskId: String, status: String)

    @Query("UPDATE upload_tasks SET progress = :progress WHERE taskId = :taskId")
    fun updateProgress(taskId: String, progress: Int)
    
    @Query("DELETE FROM upload_tasks WHERE taskId = :taskId")
    fun delete(taskId: String)
}
