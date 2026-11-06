<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ซื้อหลายชิ้นในครั้งเดียว
     * - product_variants: ตัวเลือกสินค้า (สี ขนาด รุ่น) แต่ละตัวมีราคา/สต็อกของตัวเอง
     * - cart_items: ตะกร้าสินค้า
     * - addresses: ที่อยู่จัดส่งที่ผู้ใช้บันทึกไว้
     * - order_items: สินค้าในคำสั่งซื้อ (1 คำสั่งซื้อ = 1 ร้าน หลายรายการ)
     * - order_status_histories: ประวัติสถานะคำสั่งซื้อ
     * - orders.checkout_id: กันกดสั่งซ้ำ (ส่ง checkout_id เดิม = ได้คำสั่งซื้อเดิม)
     */
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            // ชื่อหัวข้อตัวเลือก เช่น "สี / ขนาด"
            $table->string('option_name', 40)->nullable()->after('card_media');
        });

        Schema::create('product_variants', function (Blueprint $table) {
            $table->id();

            $table->foreignId('product_id')
                ->constrained('products')
                ->cascadeOnDelete();

            $table->string('name', 60);

            // null = ราคาเดียวกับสินค้า
            $table->decimal('price', 10, 2)->nullable();

            $table->unsignedInteger('stock')->default(0);
            $table->unsignedSmallInteger('sort')->default(0);

            $table->timestamps();
        });

        Schema::create('cart_items', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->foreignId('product_id')
                ->constrained('products')
                ->cascadeOnDelete();

            $table->foreignId('variant_id')
                ->nullable()
                ->constrained('product_variants')
                ->cascadeOnDelete();

            $table->unsignedInteger('quantity');

            $table->timestamps();

            $table->index(['user_id', 'product_id']);
        });

        Schema::create('addresses', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            $table->string('recipient_name', 100);
            $table->string('phone', 20);

            // บ้านเลขที่ หมู่ ซอย ถนน
            $table->string('address_line', 255);
            $table->string('subdistrict', 80);
            $table->string('district', 80);
            $table->string('province', 60);
            $table->string('postcode', 5);

            $table->boolean('is_default')->default(false);

            $table->timestamps();
        });

        Schema::create('order_items', function (Blueprint $table) {
            $table->id();

            $table->foreignId('order_id')
                ->constrained('orders')
                ->cascadeOnDelete();

            // สินค้า/ตัวเลือกถูกลบภายหลัง → ยังเห็นชื่อและราคาตอนสั่ง
            $table->foreignId('product_id')
                ->nullable()
                ->constrained('products')
                ->nullOnDelete();

            $table->foreignId('variant_id')
                ->nullable()
                ->constrained('product_variants')
                ->nullOnDelete();

            $table->string('title', 120);
            $table->string('variant_name', 60)->nullable();
            $table->decimal('unit_price', 10, 2);
            $table->unsignedInteger('quantity');
            $table->decimal('subtotal', 12, 2);

            $table->timestamps();
        });

        Schema::create('order_status_histories', function (Blueprint $table) {
            $table->id();

            $table->foreignId('order_id')
                ->constrained('orders')
                ->cascadeOnDelete();

            $table->string('status', 20);

            // buyer / seller / system
            $table->string('actor', 10);

            $table->string('note', 300)->nullable();

            $table->timestamp('created_at')->nullable();
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->string('checkout_id', 40)->nullable()->after('code');
            $table->decimal('items_total', 12, 2)->default(0)->after('quantity');

            $table->index(['buyer_id', 'checkout_id']);
        });

        // คำสั่งซื้อเดิม (สินค้าเดียว) → ย้ายเป็นรายการสินค้า
        DB::table('orders')->orderBy('id')->each(function (object $order) {
            $subtotal = round((float) $order->unit_price * (int) $order->quantity, 2);

            DB::table('order_items')->insert([
                'order_id' => $order->id,
                'product_id' => $order->product_id,
                'variant_id' => null,
                'title' => $order->product_title,
                'variant_name' => null,
                'unit_price' => $order->unit_price,
                'quantity' => $order->quantity,
                'subtotal' => $subtotal,
                'created_at' => $order->created_at,
                'updated_at' => $order->updated_at,
            ]);

            DB::table('orders')->where('id', $order->id)->update(['items_total' => $subtotal]);

            DB::table('order_status_histories')->insert([
                'order_id' => $order->id,
                'status' => $order->status,
                'actor' => 'system',
                'note' => null,
                'created_at' => $order->updated_at,
            ]);
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropIndex(['buyer_id', 'checkout_id']);
            $table->dropColumn(['checkout_id', 'items_total']);
        });

        Schema::dropIfExists('order_status_histories');
        Schema::dropIfExists('order_items');
        Schema::dropIfExists('addresses');
        Schema::dropIfExists('cart_items');
        Schema::dropIfExists('product_variants');

        Schema::table('products', function (Blueprint $table) {
            $table->dropColumn('option_name');
        });
    }
};
