<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * คำสั่งซื้อช่อง "ร้านแนะนำ" (แบนเนอร์ใหญ่บนสุด) แบบโอนพร้อมเพย์ + แนบสลิป
     * สถานะเหมือน product_promotions
     */
    public function up(): void
    {
        Schema::create('shop_promotions', function (Blueprint $table) {
            $table->id();

            $table->foreignId('shop_id')
                ->constrained('shops')
                ->cascadeOnDelete();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // key ตาม config('market.shop_promotion_plans') + ค่าตอนสั่งซื้อ
            $table->string('plan', 10);
            $table->unsignedSmallInteger('days');
            $table->decimal('amount', 10, 2);

            $table->string('status', 20)->default('awaiting_payment');

            $table->string('slip_path')->nullable();
            $table->timestamp('slip_uploaded_at')->nullable();

            $table->foreignId('reviewed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            $table->timestamp('reviewed_at')->nullable();
            $table->string('reject_reason', 300)->nullable();

            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();

            $table->timestamps();

            $table->index('status');
            $table->index(['user_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('shop_promotions');
    }
};
