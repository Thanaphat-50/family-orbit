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
        Schema::create('comment_reports', function (Blueprint $table) {
            $table->id();

            $table->foreignId('comment_id')
                ->constrained('comments')
                ->cascadeOnDelete();

            // ผู้รายงาน
            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // spam, inappropriate, harassment, scam, other
            $table->string('reason', 30);

            $table->text('details')->nullable();

            $table->timestamps();

            // คนเดียวรายงานความคิดเห็นเดียวได้ครั้งเดียว
            $table->unique([
                'comment_id',
                'user_id',
            ]);
        });

        Schema::table('comments', function (Blueprint $table) {
            // ซ่อนอัตโนมัติเมื่อถูกรายงานครบกำหนด
            $table->timestamp('hidden_at')
                ->nullable()
                ->after('content');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('comments', function (Blueprint $table) {
            $table->dropColumn('hidden_at');
        });

        Schema::dropIfExists('comment_reports');
    }
};
