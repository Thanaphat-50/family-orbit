<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // หมวดหมู่ของโพสต์ชุมชน (general, qa, news, help, event)
        // โพสต์ครอบครัวเป็น null
        Schema::table('posts', function (Blueprint $table) {
            $table->string('category', 20)
                ->nullable()
                ->after('visibility');

            $table->index([
                'visibility',
                'category',
            ]);
        });

        // โพสต์ชุมชนเดิมทั้งหมดอยู่หมวด "ทั่วไป"
        DB::table('posts')
            ->where('visibility', 'community')
            ->update(['category' => 'general']);
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('posts', function (Blueprint $table) {
            $table->dropIndex([
                'visibility',
                'category',
            ]);

            $table->dropColumn('category');
        });
    }
};
