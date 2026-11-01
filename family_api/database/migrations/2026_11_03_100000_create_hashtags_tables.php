<?php

use App\Models\Post;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// แฮชแท็กในโพสต์ (#ทำอาหาร) → กดดูโพสต์ที่มีแท็กเดียวกันได้
// ดึงจากข้อความของโพสต์อัตโนมัติ (Post::syncHashtags)
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('hashtags', function (Blueprint $table) {
            $table->id();

            // ตัวพิมพ์เล็ก ไม่มี #
            $name = $table->string('name', 50)->unique();

            // MySQL ค่าเริ่มต้นไม่สนใจวรรณยุกต์/สระบางตัว (#ไก่ = #ไก)
            // → เทียบทีละตัวอักษร (แปลงเป็นตัวพิมพ์เล็กเองแล้ว)
            if (in_array(Schema::getConnection()->getDriverName(), ['mysql', 'mariadb'], true)) {
                $name->collation('utf8mb4_bin');
            }

            $table->timestamps();
        });

        Schema::create('hashtag_post', function (Blueprint $table) {
            $table->foreignId('hashtag_id')->constrained()->cascadeOnDelete();
            $table->foreignId('post_id')->constrained()->cascadeOnDelete();
            $table->primary(['hashtag_id', 'post_id']);
            $table->index('post_id');
        });

        // โพสต์เดิมที่มี # อยู่แล้ว
        Post::query()
            ->where('content', 'like', '%#%')
            ->chunkById(200, fn ($posts) => $posts->each->syncHashtags());
    }

    public function down(): void
    {
        Schema::dropIfExists('hashtag_post');
        Schema::dropIfExists('hashtags');
    }
};
