package com.example.flutoryx_uploader.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [UploadTaskEntity::class], version = 3, exportSchema = false)
abstract class UploadDatabase : RoomDatabase() {
    abstract fun uploadDao(): UploadDao

    companion object {
        @Volatile
        private var INSTANCE: UploadDatabase? = null

        fun getDatabase(context: Context): UploadDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    UploadDatabase::class.java,
                    "flutoryx_uploader_db"
                )
                .fallbackToDestructiveMigration()
                .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
