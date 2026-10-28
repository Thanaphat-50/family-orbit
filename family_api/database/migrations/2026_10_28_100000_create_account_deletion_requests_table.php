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
        // คำขอลบบัญชี (ผู้ใช้ส่งคำขอ → ผู้ดูแลตรวจแล้วลบให้)
        Schema::create('account_deletion_requests', function (Blueprint $table) {
            $table->id();

            // ลบบัญชีแล้วแถวนี้ยังอยู่เป็นหลักฐาน (user_id เป็น null)
            $table->foreignId('user_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            // ชื่อ/อีเมลตอนขอ (เก็บไว้ดูหลังลบบัญชีแล้ว)
            $table->string('name')->nullable();
            $table->string('email')->nullable();

            // app / web
            $table->string('source', 10)->default('app');

            $table->text('reason')->nullable();

            // pending / completed / canceled / rejected
            $table->string('status', 20)->default('pending')->index();

            $table->foreignId('processed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            $table->timestamp('processed_at')->nullable();

            // หมายเหตุจากผู้ดูแล (เช่น เหตุผลที่ไม่ลบ)
            $table->text('note')->nullable();

            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('account_deletion_requests');
    }
};
