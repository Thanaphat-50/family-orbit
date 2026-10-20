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
        // รายงานผู้ใช้ (จากหน้าโปรไฟล์ในชุมชน) Admin ตรวจเอง
        Schema::create('user_reports', function (Blueprint $table) {
            $table->id();

            // ผู้ใช้ที่ถูกรายงาน
            $table->foreignId('reported_user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // ผู้รายงาน
            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // ตาม UserReport::REASONS
            $table->string('reason', 30);

            $table->text('details')->nullable();

            $table->timestamps();

            // คนเดียวรายงานผู้ใช้คนเดียวได้ครั้งเดียว
            $table->unique([
                'reported_user_id',
                'user_id',
            ]);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('user_reports');
    }
};
