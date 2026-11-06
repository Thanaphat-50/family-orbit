<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * หน้าสินค้าแบบใหม่
     * - conversations.shop_id: ห้องแชทนี้เริ่มจากการทักร้าน (คนนอกกลุ่มคุยกับร้านได้)
     * - shops.ship_within_days: ร้านจัดส่งภายในกี่วันหลังชำระเงิน
     * - saved_products: สินค้าที่ผู้ใช้กดบันทึกไว้
     */
    public function up(): void
    {
        Schema::table('conversations', function (Blueprint $table) {
            $table->foreignId('shop_id')
                ->nullable()
                ->after('user_two_id')
                ->constrained('shops')
                ->nullOnDelete();
        });

        Schema::table('shops', function (Blueprint $table) {
            $table->unsignedTinyInteger('ship_within_days')->nullable()->after('delivery_methods');
        });

        Schema::create('saved_products', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->foreignId('product_id')
                ->constrained('products')
                ->cascadeOnDelete();

            $table->timestamps();

            $table->unique(['user_id', 'product_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('saved_products');

        Schema::table('shops', function (Blueprint $table) {
            $table->dropColumn('ship_within_days');
        });

        Schema::table('conversations', function (Blueprint $table) {
            $table->dropConstrainedForeignId('shop_id');
        });
    }
};
