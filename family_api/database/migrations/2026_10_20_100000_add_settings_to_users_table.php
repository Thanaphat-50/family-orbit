<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // แชร์ตำแหน่งกับครอบครัว (ปิดได้ในหน้าตั้งค่า)
            $table->boolean('location_sharing')
                ->default(true)
                ->after('profile_photo');

            // เปิด/ปิดการแจ้งเตือนแต่ละประเภท เช่น {"new_post": false}
            // ไม่มีค่า = เปิด
            $table->json('notification_settings')
                ->nullable()
                ->after('location_sharing');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'location_sharing',
                'notification_settings',
            ]);
        });
    }
};
