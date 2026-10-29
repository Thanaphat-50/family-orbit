<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// - posts.shared_post_id: โพสต์ที่แชร์ต่อมาจากโพสต์ไหน
//   (ไม่ผูก Foreign key → ต้นฉบับถูกลบแล้วยังรู้ว่าเป็นโพสต์ที่แชร์มา)
// - interactions: ประวัติการใช้งาน (ถูกใจ / ความคิดเห็น / แชร์ / ติดตาม)
//   ใช้แสดงในหน้าประวัติ และจัดฟีด "สำหรับคุณ" + แนะนำคนที่ชอบคล้ายกัน
// - follows: การติดตามผู้ใช้อื่น (ไม่ต้องรออนุมัติ)
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('posts', function (Blueprint $table) {
            $table->unsignedBigInteger('shared_post_id')->nullable()->after('content');

            $table->index('shared_post_id');
        });

        Schema::create('interactions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('type', 20);
            $table->foreignId('post_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignId('target_user_id')->nullable()->constrained('users')->cascadeOnDelete();
            $table->json('meta')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'created_at']);
            $table->index(['type', 'created_at']);
        });

        Schema::create('follows', function (Blueprint $table) {
            $table->id();
            $table->foreignId('follower_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('followee_id')->constrained('users')->cascadeOnDelete();
            $table->timestamps();

            $table->unique(['follower_id', 'followee_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('follows');
        Schema::dropIfExists('interactions');

        Schema::table('posts', function (Blueprint $table) {
            $table->dropIndex(['shared_post_id']);

            $table->dropColumn('shared_post_id');
        });
    }
};
