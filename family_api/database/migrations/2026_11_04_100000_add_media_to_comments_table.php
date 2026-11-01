<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// แนบรูป / GIF / วิดีโอ ในความคิดเห็นได้ 1 ไฟล์
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('comments', function (Blueprint $table) {
            $table->string('media_type', 10)->nullable()->after('content');
            $table->string('media_path')->nullable()->after('media_type');
            // รูปตัวอย่างของวิดีโอ
            $table->string('media_thumbnail_path')->nullable()->after('media_path');
            $table->unsignedSmallInteger('media_width')->nullable()->after('media_thumbnail_path');
            $table->unsignedSmallInteger('media_height')->nullable()->after('media_width');
        });

        // ความคิดเห็นที่มีแต่ไฟล์ ไม่มีข้อความ
        Schema::table('comments', function (Blueprint $table) {
            $table->text('content')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('comments', function (Blueprint $table) {
            $table->dropColumn([
                'media_type',
                'media_path',
                'media_thumbnail_path',
                'media_width',
                'media_height',
            ]);
        });
    }
};
