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
        // สินค้าของร้าน (ช่วงเปิดร้านฟรี: ร้านละไม่เกิน 30 ชิ้น)
        Schema::create('products', function (Blueprint $table) {
            $table->id();

            $table->foreignId('shop_id')
                ->constrained('shops')
                ->cascadeOnDelete();

            $table->string('title', 120);

            $table->text('description')->nullable();

            // null = สอบถามราคา
            $table->decimal('price', 10, 2)->nullable();

            // หมวดตาม config('market.categories')
            $table->string('category', 20);

            // active = แสดง, hidden = เจ้าของร้านซ่อนไว้
            $table->string('status', 20)->default('active');

            // ซ่อนโดย Admin หรือถูกรายงานครบ
            $table->timestamp('hidden_at')->nullable();

            $table->unsignedInteger('views')->default(0);

            $table->timestamps();

            $table->index(['shop_id', 'status']);
            $table->index(['category', 'created_at']);
        });

        // รูปสินค้า (ชิ้นละไม่เกิน 5 รูป)
        Schema::create('product_images', function (Blueprint $table) {
            $table->id();

            $table->foreignId('product_id')
                ->constrained('products')
                ->cascadeOnDelete();

            $table->string('path');

            $table->unsignedTinyInteger('sort')->default(0);

            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('product_images');
        Schema::dropIfExists('products');
    }
};
