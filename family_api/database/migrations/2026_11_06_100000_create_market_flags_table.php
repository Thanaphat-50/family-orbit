<?php

use App\Services\MarketScreening;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ร้านเปิดขายได้ทันที (ไม่ต้องรอ Admin อนุมัติ)
     * แทนด้วยการตรวจสินค้าต้องห้ามอัตโนมัติ → รายการตรวจพบ + แจ้งเตือนผู้ดูแล
     */
    public function up(): void
    {
        Schema::create('market_flags', function (Blueprint $table) {
            $table->id();

            // สินค้า (Product) หรือร้าน (Shop) ที่ตรวจพบ
            $table->morphs('flaggable');

            $table->foreignId('shop_id')
                ->constrained('shops')
                ->cascadeOnDelete();

            // key ตาม config('market.prohibited') และคำที่พบ
            $table->json('categories');
            $table->json('terms');

            // ลายนิ้วมือของคำที่พบ: คำเดิมที่ผู้ดูแลตรวจแล้ว ไม่แจ้งซ้ำ
            $table->string('fingerprint', 64);

            $table->string('excerpt', 300)->nullable();

            // open → dismissed (ไม่ผิดกฎ) / actioned (ซ่อนสินค้า / ระงับร้านแล้ว)
            $table->string('status', 20)->default('open');

            $table->foreignId('reviewed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            $table->timestamp('reviewed_at')->nullable();

            $table->timestamps();

            $table->index(['status', 'created_at']);
        });

        // ร้านที่รออนุมัติอยู่ → เปิดขายเลย
        DB::table('shops')
            ->where('status', 'pending')
            ->update(['status' => 'active', 'approved_at' => now(), 'updated_at' => now()]);

        // ตรวจร้านและสินค้าที่มีอยู่แล้วหนึ่งรอบ
        app(MarketScreening::class)->screenAll();
    }

    public function down(): void
    {
        Schema::dropIfExists('market_flags');
    }
};
