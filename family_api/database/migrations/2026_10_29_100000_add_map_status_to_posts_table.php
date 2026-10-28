<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// โพสต์ครอบครัวที่แสดงเป็นข้อความข้างตำแหน่งบนแผนที่ (เช่น "ทำงานอยู่")
// แสดงจนถึง map_status_until (null = ไม่แสดง)
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('posts', function (Blueprint $table) {
            $table->timestamp('map_status_until')->nullable()->after('content');

            $table->index('map_status_until');
        });
    }

    public function down(): void
    {
        Schema::table('posts', function (Blueprint $table) {
            $table->dropIndex(['map_status_until']);

            $table->dropColumn('map_status_until');
        });
    }
};
