<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ร้านจัดการคำสั่งซื้อ
     * - carrier: บริษัทขนส่งที่ร้านเลือกตอนส่งสินค้า (key ใน config market.carriers)
     * - refund_status: ยกเลิกหลังลูกค้าจ่ายเงินแล้ว → pending (ร้านต้องคืนเงิน) → refunded
     * - refund_note: ร้านบอกว่าคืนเงินช่องทางไหน / เลขอ้างอิง
     *
     * รันซ้ำได้ (MySQL เพิ่มคอลัมน์ทีละคำสั่ง ถ้าล้มกลางทาง รอบถัดไปข้ามส่วนที่มีแล้ว)
     */
    public function up(): void
    {
        if (!Schema::hasColumn('orders', 'carrier')) {
            Schema::table('orders', function (Blueprint $table) {
                $table->string('carrier', 30)->nullable()->after('tracking_number');
            });
        }

        if (!Schema::hasColumn('orders', 'refund_status')) {
            Schema::table('orders', function (Blueprint $table) {
                $table->string('refund_status', 20)->nullable()->after('cancelled_by');
            });
        }

        if (!Schema::hasColumn('orders', 'refund_note')) {
            Schema::table('orders', function (Blueprint $table) {
                $table->string('refund_note', 300)->nullable()->after('refund_status');
            });
        }

        if (!Schema::hasColumn('orders', 'refunded_at')) {
            Schema::table('orders', function (Blueprint $table) {
                $table->timestamp('refunded_at')->nullable()->after('cancelled_at');
            });
        }
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn(['carrier', 'refund_status', 'refund_note', 'refunded_at']);
        });
    }
};
