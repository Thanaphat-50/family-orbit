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
        // มือถือแต่ละเครื่อง สำหรับส่งแจ้งเตือนเด้ง (Firebase Cloud Messaging)
        Schema::create('device_tokens', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // การล็อกอินที่ลงทะเบียนเครื่องนี้
            // ออกจากระบบ (ลบ Token ของแอป) → แถวนี้ถูกลบตาม ไม่ส่งแจ้งเตือนอีก
            $table->foreignId('access_token_id')
                ->nullable()
                ->constrained('personal_access_tokens')
                ->cascadeOnDelete();

            // รหัสเครื่องจาก Firebase (FID) 1 เครื่อง = 1 รหัส
            // ล็อกอินบัญชีใหม่ในเครื่องเดิม → ย้ายเจ้าของ
            $table->string('token', 512)->unique();

            $table->string('platform', 20)->default('android');

            $table->timestamp('last_used_at')->nullable();

            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('device_tokens');
    }
};
