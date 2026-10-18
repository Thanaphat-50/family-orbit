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
        // รายงานสินค้า (ครบตามที่ตั้งไว้ → ซ่อนสินค้าอัตโนมัติ)
        Schema::create('product_reports', function (Blueprint $table) {
            $table->id();

            $table->foreignId('product_id')
                ->constrained('products')
                ->cascadeOnDelete();

            // ผู้รายงาน
            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // ตาม config('market.report_reasons')
            $table->string('reason', 30);

            $table->text('details')->nullable();

            $table->timestamps();

            // คนเดียวรายงานสินค้าเดียวได้ครั้งเดียว
            $table->unique([
                'product_id',
                'user_id',
            ]);
        });

        // รายงานร้าน (Admin ตรวจแล้วตัดสินใจระงับร้านเอง)
        Schema::create('shop_reports', function (Blueprint $table) {
            $table->id();

            $table->foreignId('shop_id')
                ->constrained('shops')
                ->cascadeOnDelete();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->string('reason', 30);

            $table->text('details')->nullable();

            $table->timestamps();

            $table->unique([
                'shop_id',
                'user_id',
            ]);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('shop_reports');
        Schema::dropIfExists('product_reports');
    }
};
