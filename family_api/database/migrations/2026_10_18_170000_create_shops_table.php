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
        // ร้านค้าในตลาด (ผู้ใช้ 1 คน มีได้ 1 ร้าน)
        Schema::create('shops', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->unique()
                ->constrained('users')
                ->cascadeOnDelete();

            $table->string('name', 80);

            $table->text('description')->nullable();

            // หมวดตาม config('market.categories')
            $table->string('category', 20);

            // ช่องทางติดต่อที่เจ้าของร้านเลือกเปิดเอง
            $table->string('phone', 20);
            $table->string('line_id', 50)->nullable();

            // พื้นที่ขาย (ข้อความ ไม่ใช่ตำแหน่ง GPS)
            $table->string('province', 40);
            $table->string('district', 80)->nullable();

            $table->string('logo_path')->nullable();

            // pending → active / rejected, active → suspended
            $table->string('status', 20)->default('pending');

            // เหตุผลที่ Admin แจ้งเจ้าของร้าน (ไม่ผ่าน / ระงับ)
            $table->string('status_reason', 500)->nullable();

            $table->timestamp('approved_at')->nullable();

            // ยอมรับกฎผู้ขายตอนสมัคร
            $table->timestamp('terms_accepted_at')->nullable();

            $table->timestamps();

            $table->index(['status', 'province']);
            $table->index(['status', 'category']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('shops');
    }
};
