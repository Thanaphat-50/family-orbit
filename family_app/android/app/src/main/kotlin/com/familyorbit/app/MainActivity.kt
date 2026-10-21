package com.familyorbit.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        createNotificationChannel()
    }

    // ช่องแจ้งเตือนหลักของแอป (Server ส่งมาที่ช่อง klaikan_default)
    // ผู้ใช้เปิด/ปิดได้ในการตั้งค่าแอปของ Android
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            "klaikan_default",
            "การแจ้งเตือน",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "โพสต์ ความคิดเห็น กิจกรรม และข่าวจากครอบครัว"
        }

        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }
}
