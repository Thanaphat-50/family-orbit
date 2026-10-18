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
        Schema::create('post_reports', function (Blueprint $table) {
            $table->id();

            $table->foreignId('post_id')
                ->constrained('posts')
                ->cascadeOnDelete();

            // ผู้รายงาน
            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // spam, inappropriate, harassment, scam, other
            $table->string('reason', 30);

            $table->text('details')->nullable();

            $table->timestamps();

            // คนเดียวรายงานโพสต์เดียวได้ครั้งเดียว
            $table->unique([
                'post_id',
                'user_id',
            ]);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('post_reports');
    }
};
