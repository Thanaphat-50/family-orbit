<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * รีวิวร้าน: 1 คนรีวิวได้ 1 ครั้งต่อร้าน (แก้ไขได้) / Admin ซ่อนรีวิวได้
     */
    public function up(): void
    {
        Schema::create('shop_reviews', function (Blueprint $table) {
            $table->id();

            $table->foreignId('shop_id')
                ->constrained('shops')
                ->cascadeOnDelete();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // 1–5 ดาว
            $table->unsignedTinyInteger('rating');

            $table->text('comment')->nullable();

            $table->timestamp('hidden_at')->nullable();

            $table->timestamps();

            $table->unique(['shop_id', 'user_id']);
            $table->index(['shop_id', 'hidden_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('shop_reviews');
    }
};
