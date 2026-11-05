<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * คำสั่งซื้อสินค้า (ผู้ซื้อ → ร้าน) 1 คำสั่งซื้อ = สินค้า 1 รายการ
     * เงินโอนเข้าร้านโดยตรง แอปไม่ได้รับเงินแทน (สถานะดู App\Models\Order)
     */
    public function up(): void
    {
        Schema::create('orders', function (Blueprint $table) {
            $table->id();

            // เลขที่คำสั่งซื้อที่แสดงให้ผู้ใช้เห็น เช่น OR2611051234AB
            $table->string('code', 20)->unique();

            $table->foreignId('buyer_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->foreignId('shop_id')
                ->constrained('shops')
                ->cascadeOnDelete();

            // สินค้าถูกลบภายหลัง → ยังเห็นชื่อและราคาตอนสั่ง
            $table->foreignId('product_id')
                ->nullable()
                ->constrained('products')
                ->nullOnDelete();

            $table->string('product_title', 120);
            $table->decimal('unit_price', 10, 2);
            $table->unsignedInteger('quantity');
            $table->decimal('shipping_fee', 10, 2)->default(0);
            $table->decimal('total', 12, 2);

            // key ตาม config('market.delivery_methods') / config('market.payment_methods')
            $table->string('delivery_method', 20);
            $table->string('payment_method', 20);

            $table->string('recipient_name', 100);
            $table->string('recipient_phone', 20);
            $table->text('address')->nullable();
            $table->string('note', 500)->nullable();

            $table->string('status', 20)->default('awaiting_payment');

            // โอนเงิน: ต้องแนบสลิปภายในเวลานี้ (เกิน → ยกเลิกเอง คืนสต็อก)
            $table->timestamp('payment_due_at')->nullable();

            $table->string('slip_path')->nullable();
            $table->timestamp('slip_uploaded_at')->nullable();

            // ร้านแจ้งว่าสลิปไม่ถูกต้อง
            $table->string('payment_note', 300)->nullable();

            // เลขพัสดุ / ข้อความจากร้านตอนส่ง (เช่น จุดนัดรับ)
            $table->string('tracking_number', 60)->nullable();
            $table->string('seller_note', 500)->nullable();

            $table->string('cancel_reason', 300)->nullable();

            // buyer / seller / system
            $table->string('cancelled_by', 10)->nullable();

            $table->timestamp('paid_at')->nullable();
            $table->timestamp('shipped_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();

            $table->timestamps();

            $table->index(['shop_id', 'status']);
            $table->index(['buyer_id', 'created_at']);
            $table->index(['status', 'updated_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('orders');
    }
};
