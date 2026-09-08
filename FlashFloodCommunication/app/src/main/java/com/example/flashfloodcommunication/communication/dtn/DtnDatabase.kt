package com.example.flashfloodcommunication.communication.dtn

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [AlertEntity::class], version = 2, exportSchema = false) // increment version if you changed fields
abstract class DtnDatabase : RoomDatabase() {
    abstract fun alertDao(): AlertDao

    companion object {
        @Volatile
        private var INSTANCE: DtnDatabase? = null

        fun getDatabase(context: Context): DtnDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    DtnDatabase::class.java,
                    "dtn_mesh_database"
                )
                    .fallbackToDestructiveMigration() // Destroys and recreates DB on schema mismatch instead of crashing
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
