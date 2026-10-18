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
        Schema::table('posts', function (Blueprint $table) {
            // family    = เห็นเฉพาะครอบครัว (โพสต์เดิมทั้งหมด)
            // community = ผู้ใช้ทุกคนในแอปเห็นได้
            $table->string('visibility', 20)
                ->default('family')
                ->after('user_id');

            // ซ่อนอัตโนมัติเมื่อถูกรายงานครบกำหนด
            $table->timestamp('hidden_at')
                ->nullable()
                ->after('content');

            // ช่วยให้ดึงฟีดชุมชนได้เร็ว
            $table->index([
                'visibility',
                'hidden_at',
                'created_at',
            ]);
        });

        Schema::table('users', function (Blueprint $table) {
            // เวลาที่ยอมรับกฎชุมชน (ต้องยอมรับก่อนโพสต์ชุมชน)
            $table->timestamp('community_terms_accepted_at')
                ->nullable()
                ->after('profile_photo');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('posts', function (Blueprint $table) {
            $table->dropIndex([
                'visibility',
                'hidden_at',
                'created_at',
            ]);

            $table->dropColumn([
                'visibility',
                'hidden_at',
            ]);
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('community_terms_accepted_at');
        });
    }
};
