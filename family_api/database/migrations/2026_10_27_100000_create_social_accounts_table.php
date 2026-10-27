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
        // บัญชี Google / LINE / Facebook ที่ผูกกับผู้ใช้
        Schema::create('social_accounts', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // google / line / facebook
            $table->string('provider', 20);

            // รหัสผู้ใช้ของผู้ให้บริการ (sub / userId / id)
            $table->string('provider_user_id');

            $table->string('email')->nullable();

            $table->timestamps();

            // บัญชีของผู้ให้บริการ 1 บัญชี ผูกได้กับผู้ใช้คนเดียว
            $table->unique(['provider', 'provider_user_id']);

            // ผู้ใช้ 1 คน ผูกผู้ให้บริการแต่ละเจ้าได้ 1 บัญชี
            $table->unique(['user_id', 'provider']);
        });

        // สมัครด้วย Google / LINE / Facebook → อาจยังไม่มีรหัสผ่าน หรือไม่มีอีเมล
        Schema::table('users', function (Blueprint $table) {
            $table->string('password')->nullable()->change();
            $table->string('email')->nullable()->change();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('social_accounts');

        // ผู้ใช้ที่ไม่มีอีเมล / รหัสผ่าน จะย้อนกลับไม่ได้ (คอลัมน์บังคับค่า)
        Schema::table('users', function (Blueprint $table) {
            $table->string('password')->nullable(false)->change();
            $table->string('email')->nullable(false)->change();
        });
    }
};
