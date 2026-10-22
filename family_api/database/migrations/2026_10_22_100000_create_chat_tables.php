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
        // ห้องแชทส่วนตัว 2 คน (คนในครอบครัวเดียวกัน)
        Schema::create('conversations', function (Blueprint $table) {
            $table->id();

            // เก็บ id ที่น้อยกว่าไว้ที่ user_one เสมอ → 1 คู่มีห้องเดียว
            $table->foreignId('user_one_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->foreignId('user_two_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // ข้อความล่าสุดที่แต่ละคนอ่านแล้ว (นับข้อความที่ยังไม่อ่าน)
            $table->unsignedBigInteger('user_one_read_id')->nullable();
            $table->unsignedBigInteger('user_two_read_id')->nullable();

            $table->timestamp('last_message_at')->nullable()->index();

            $table->timestamps();

            $table->unique([
                'user_one_id',
                'user_two_id',
            ]);
        });

        Schema::create('chat_messages', function (Blueprint $table) {
            $table->id();

            $table->foreignId('conversation_id')
                ->constrained('conversations')
                ->cascadeOnDelete();

            $table->foreignId('sender_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->text('body')->nullable();

            // รูปแนบ (เก็บแบบส่วนตัวเหมือนรูปในโพสต์)
            $table->string('image_path')->nullable();

            $table->timestamps();

            $table->index([
                'conversation_id',
                'id',
            ]);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('chat_messages');
        Schema::dropIfExists('conversations');
    }
};
