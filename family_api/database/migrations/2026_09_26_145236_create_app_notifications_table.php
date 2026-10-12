<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('app_notifications', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->foreignId('family_id')
                ->nullable()
                ->constrained('families')
                ->cascadeOnDelete();

            $table->string('type', 50);

            $table->string('title');

            $table->text('message');

            $table->json('data')
                ->nullable();

            $table->boolean('is_read')
                ->default(false);

            $table->timestamps();

            $table->index([
                'user_id',
                'is_read'
            ]);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists(
            'app_notifications'
        );
    }
};