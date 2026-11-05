<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * สั่งซื้อในแอป
     * - สินค้า: จำนวนในสต็อก, ค่าส่ง, หน้าปกการ์ด (รูป / วิดีโอ)
     * - ร้าน: วิธีรับเงิน + พร้อมเพย์ / บัญชีธนาคารของร้าน
     */
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            // ขายได้ระบบลดให้เอง ถึง 0 = สินค้าหมด
            $table->unsignedInteger('stock')->default(1)->after('price');

            // ใช้กับส่งพัสดุ / ส่งถึงบ้าน (null = ส่งฟรี)
            $table->decimal('shipping_fee', 10, 2)->nullable()->after('stock');

            // image = รูปแรก, video = เล่นวิดีโอสินค้าบนการ์ด
            $table->string('card_media', 10)->default('image')->after('video_thumbnail_path');
        });

        Schema::table('shops', function (Blueprint $table) {
            // key ตาม config('market.payment_methods') (null = ยังไม่เปิดรับคำสั่งซื้อ)
            $table->json('payment_methods')->nullable()->after('delivery_methods');

            $table->string('promptpay_id', 20)->nullable()->after('payment_methods');
            $table->string('bank_name', 60)->nullable()->after('promptpay_id');
            $table->string('bank_account_number', 30)->nullable()->after('bank_name');
            $table->string('bank_account_name', 100)->nullable()->after('bank_account_number');
        });
    }

    public function down(): void
    {
        Schema::table('shops', function (Blueprint $table) {
            $table->dropColumn([
                'payment_methods',
                'promptpay_id',
                'bank_name',
                'bank_account_number',
                'bank_account_name',
            ]);
        });

        Schema::table('products', function (Blueprint $table) {
            $table->dropColumn(['stock', 'shipping_fee', 'card_media']);
        });
    }
};
