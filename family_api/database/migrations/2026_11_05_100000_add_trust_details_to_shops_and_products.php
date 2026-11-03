<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ข้อมูลร้านละเอียดขึ้น (เวลาเปิด-ปิด / วิธีรับสินค้า / รูปหน้าร้าน / วิดีโอแนะนำ)
     * + วิดีโอแนะนำสินค้า + สินค้าขึ้นช่องแนะนำถึงเมื่อไร
     */
    public function up(): void
    {
        Schema::table('shops', function (Blueprint $table) {
            // ข้อความอิสระ เช่น "ทุกวัน 08:00–18:00"
            $table->string('opening_hours', 200)->nullable()->after('district');

            // key ตาม config('market.delivery_methods')
            $table->json('delivery_methods')->nullable()->after('opening_hours');

            $table->string('video_path')->nullable()->after('logo_path');
            $table->string('video_thumbnail_path')->nullable()->after('video_path');
        });

        Schema::table('products', function (Blueprint $table) {
            $table->string('video_path')->nullable();
            $table->string('video_thumbnail_path')->nullable();

            // ช่องแนะนำแบบชำระเงิน (ต่ออายุได้: นับต่อจากวันหมดเดิม)
            $table->timestamp('featured_until')->nullable();

            $table->index(['category', 'featured_until']);
        });

        Schema::create('shop_images', function (Blueprint $table) {
            $table->id();

            $table->foreignId('shop_id')
                ->constrained('shops')
                ->cascadeOnDelete();

            $table->string('path');

            $table->unsignedSmallInteger('sort')->default(0);

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('shop_images');

        Schema::table('products', function (Blueprint $table) {
            $table->dropIndex(['category', 'featured_until']);
            $table->dropColumn(['video_path', 'video_thumbnail_path', 'featured_until']);
        });

        Schema::table('shops', function (Blueprint $table) {
            $table->dropColumn(['opening_hours', 'delivery_methods', 'video_path', 'video_thumbnail_path']);
        });
    }
};
