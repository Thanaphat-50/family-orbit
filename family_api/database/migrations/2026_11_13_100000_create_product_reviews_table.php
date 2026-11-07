<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * รีวิวสินค้าจากผู้ซื้อจริง (รีวิวได้เมื่อคำสั่งซื้อสำเร็จ 1 ครั้งต่อสินค้าต่อคำสั่งซื้อ)
     * Admin ซ่อนรีวิวที่ไม่เหมาะสมได้ (hidden_at)
     */
    public function up(): void
    {
        // รันซ้ำได้ (deploy ที่ล้มกลางทาง)
        if (Schema::hasTable('product_reviews')) {
            return;
        }

        Schema::create('product_reviews', function (Blueprint $table) {
            $table->id();

            $table->foreignId('product_id')
                ->constrained('products')
                ->cascadeOnDelete();

            $table->foreignId('order_id')
                ->constrained('orders')
                ->cascadeOnDelete();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->foreignId('shop_id')
                ->constrained('shops')
                ->cascadeOnDelete();

            $table->unsignedTinyInteger('rating');
            $table->string('comment', 500)->nullable();

            // ตัวเลือกที่ซื้อ (เช่น ขนาด M)
            $table->string('variant_name', 60)->nullable();

            $table->timestamp('hidden_at')->nullable();

            $table->timestamps();

            $table->unique(['order_id', 'product_id']);
            $table->index(['product_id', 'hidden_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_reviews');
    }
};
