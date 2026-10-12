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
        Schema::table('activities', function (Blueprint $table) {
            // ครอบครัวที่กิจกรรมนี้แชร์ให้
            // ถ้าเป็นกิจกรรมส่วนตัวจะเป็น NULL
            $table->foreignId('family_id')
                ->nullable()
                ->after('user_id')
                ->constrained('families')
                ->cascadeOnDelete();

            // private = เจ้าของเห็นคนเดียว
            // family  = สมาชิกในครอบครัวเห็นได้
            $table->string('visibility', 20)
                ->default('private')
                ->after('family_id');

            // ช่วยให้ค้นกิจกรรมของครอบครัวได้เร็วขึ้น
            $table->index([
                'family_id',
                'visibility',
            ]);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('activities', function (Blueprint $table) {
            $table->dropIndex([
                'family_id',
                'visibility',
            ]);

            $table->dropConstrainedForeignId(
                'family_id'
            );

            $table->dropColumn(
                'visibility'
            );
        });
    }
};