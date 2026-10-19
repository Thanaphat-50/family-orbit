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
        // ร้านแนะนำ (ร้านที่เช่าพื้นที่): แสดงบนสุดของตลาดจนถึงเวลานี้
        // null หรือเลยเวลาแล้ว = ร้านปกติ
        Schema::table('shops', function (Blueprint $table) {
            $table->timestamp('featured_until')
                ->nullable()
                ->after('approved_at');

            $table->index([
                'status',
                'featured_until',
            ]);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('shops', function (Blueprint $table) {
            $table->dropIndex([
                'status',
                'featured_until',
            ]);

            $table->dropColumn('featured_until');
        });
    }
};
