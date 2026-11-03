<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * คำสั่งซื้อช่องแนะนำสินค้า (โอนพร้อมเพย์ + แนบสลิป → Admin ตรวจ)
     * awaiting_payment → pending_review → approved / rejected
     * awaiting_payment → cancelled (ผู้ขายยกเลิก หรือหมดเวลาแนบสลิป)
     */
    public function up(): void
    {
        Schema::create('product_promotions', function (Blueprint $table) {
            $table->id();

            $table->foreignId('product_id')
                ->constrained('products')
                ->cascadeOnDelete();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // key ตาม config('market.promotion_plans') + ค่าตอนสั่งซื้อ (ราคาเปลี่ยนทีหลังไม่กระทบ)
            $table->string('plan', 10);
            $table->unsignedSmallInteger('days');
            $table->decimal('amount', 10, 2);

            // หมวดของสินค้าตอนสั่งซื้อ (ช่องแนะนำจำกัดต่อหมวด)
            $table->string('category', 20);

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

            $table->index(['status', 'category']);
            $table->index(['user_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_promotions');
    }
};
