<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ประวัติการชำระเงินของคำสั่งซื้อ (ทุกครั้งที่แนบสลิป)
     * status: verified = ระบบตรวจสลิปผ่าน / confirmed = ร้านยืนยันเอง /
     *         rejected = สลิปไม่ผ่าน / review = รอร้านตรวจ (ตรวจอัตโนมัติไม่ได้)
     * trans_ref: เลขอ้างอิงธุรกรรมจากสลิป (ใช้ซ้ำไม่ได้)
     */
    public function up(): void
    {
        Schema::create('payment_transactions', function (Blueprint $table) {
            $table->id();

            $table->foreignId('order_id')
                ->constrained('orders')
                ->cascadeOnDelete();

            $table->string('method', 20);
            $table->decimal('amount', 12, 2);

            $table->string('status', 20);

            // easyslip / manual
            $table->string('provider', 20);

            $table->string('trans_ref', 64)->nullable()->index();
            $table->decimal('slip_amount', 12, 2)->nullable();
            $table->timestamp('slip_date')->nullable();
            $table->string('receiver_account', 40)->nullable();

            $table->string('reason', 300)->nullable();

            $table->timestamp('verified_at')->nullable();

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payment_transactions');
    }
};
