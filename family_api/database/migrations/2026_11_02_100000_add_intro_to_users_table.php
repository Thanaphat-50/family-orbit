<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// ข้อมูลแนะนำตัวบนหน้าโปรไฟล์ (คนในชุมชนเห็นได้ทุกช่อง ไม่บังคับกรอก)
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->text('bio')->nullable()->after('profile_photo');
            $table->string('occupation', 80)->nullable()->after('bio');
            $table->string('education', 80)->nullable()->after('occupation');
            $table->string('province', 60)->nullable()->after('education');
            $table->string('interests', 150)->nullable()->after('province');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['bio', 'occupation', 'education', 'province', 'interests']);
        });
    }
};
