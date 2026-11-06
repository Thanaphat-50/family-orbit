<?php

namespace Tests\Feature;

use App\Models\Address;
use App\Models\CartItem;
use App\Models\Order;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

// ตัวเลือกสินค้า + ตะกร้า + ที่อยู่ + สั่งซื้อหลายร้านในครั้งเดียว
class CheckoutTest extends TestCase
{
    use RefreshDatabase;

    private function shop(array $fields = []): Shop
    {
        return Shop::create([
            'user_id' => User::factory()->create()->id,
            'name' => 'ร้าน ' . uniqid(),
            'category' => 'clothing',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => Shop::STATUS_ACTIVE,
            'delivery_methods' => ['shipping', 'storefront'],
            'payment_methods' => ['promptpay', 'cod', 'cash'],
            'promptpay_id' => '0899999999',
            'bank_account_name' => 'ร้านทดสอบ',
            ...$fields,
        ]);
    }

    private function product(Shop $shop, array $fields = []): Product
    {
        return $shop->products()->create([
            'title' => 'เสื้อยืด',
            'price' => 200,
            'stock' => 10,
            'shipping_fee' => 40,
            'category' => 'clothing',
            'status' => Product::STATUS_ACTIVE,
            ...$fields,
        ]);
    }

    private function address(User $user): Address
    {
        Sanctum::actingAs($user);

        $id = $this->postJson('/api/addresses', [
            'recipient_name' => 'คุณแม่',
            'phone' => '081-111-2222',
            'address_line' => '99/1 ถ.นิมมาน',
            'subdistrict' => 'สุเทพ',
            'district' => 'เมืองเชียงใหม่',
            'province' => 'เชียงใหม่',
            'postcode' => '50200',
        ])->assertCreated()->json('address.id');

        return Address::findOrFail($id);
    }

    public function test_seller_adds_variants_and_buyer_sees_them(): void
    {
        $shop = $this->shop();
        $product = $this->product($shop);
        $product->images()->create(['path' => 'product_images/a.png', 'sort' => 0]);

        Sanctum::actingAs($shop->owner);

        $this->post("/api/my-shop/products/{$product->id}/update", [
            'title' => $product->title,
            'price' => 200,
            'category' => 'clothing',
            'variants_present' => 1,
            'option_name' => 'ขนาด',
            'variants' => [
                ['name' => 'M', 'stock' => 3],
                ['name' => 'XL', 'price' => 250, 'stock' => 2],
            ],
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonCount(2, 'product.variants')
            ->assertJsonPath('product.option_name', 'ขนาด')
            // สต็อกรวม = ผลรวมตัวเลือก
            ->assertJsonPath('product.stock', 5);

        $ids = $product->variants()->pluck('id');

        // แก้ตัวเดิม + ลบตัวที่ไม่ได้ส่ง
        $this->post("/api/my-shop/products/{$product->id}/update", [
            'title' => $product->title,
            'price' => 200,
            'category' => 'clothing',
            'variants_present' => 1,
            'variants' => [['id' => $ids[0], 'name' => 'M', 'stock' => 7]],
        ], ['Accept' => 'application/json'])->assertOk()->assertJsonPath('product.stock', 7);

        $this->assertSame(1, $product->variants()->count());

        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/market/products/{$product->id}")
            ->assertJsonPath('product.variants.0.name', 'M')
            ->assertJsonPath('product.variants.0.price', 200)
            ->assertJsonPath('product.price_range.min', 200);
    }

    public function test_cart_add_update_and_problems(): void
    {
        $shop = $this->shop();
        $shirt = $this->product($shop);
        $sized = $this->product($shop, ['title' => 'กางเกง', 'stock' => 0]);
        $small = $sized->variants()->create(['name' => 'S', 'price' => 300, 'stock' => 2]);
        $sized->syncStockFromVariants();

        $buyer = User::factory()->create();
        Sanctum::actingAs($buyer);

        $this->postJson('/api/cart', ['product_id' => $shirt->id, 'quantity' => 2])->assertCreated()->assertJsonPath('count', 2);
        $this->postJson('/api/cart', ['product_id' => $shirt->id])->assertCreated()->assertJsonPath('count', 3);

        // มีตัวเลือกแต่ไม่ได้เลือก
        $this->postJson('/api/cart', ['product_id' => $sized->id])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'กรุณาเลือกตัวเลือกสินค้า');

        // เพิ่มเกินสต็อก → ใส่เท่าที่มี
        $this->postJson('/api/cart', ['product_id' => $sized->id, 'variant_id' => $small->id, 'quantity' => 5])
            ->assertCreated();

        $this->assertSame(2, CartItem::where('variant_id', $small->id)->value('quantity'));

        // สินค้าของตัวเองใส่ตะกร้าไม่ได้
        Sanctum::actingAs($shop->owner);
        $this->postJson('/api/cart', ['product_id' => $shirt->id])->assertUnprocessable();

        Sanctum::actingAs($buyer);

        // ร้านปิด → ยังเห็นในตะกร้าแต่ขึ้นว่าสั่งไม่ได้
        $shirt->update(['status' => Product::STATUS_HIDDEN]);

        $items = collect($this->getJson('/api/cart')->assertOk()->json('items'))->keyBy('variant_id');

        $this->assertSame('สินค้านี้ไม่มีขายแล้ว', $items['']['problem']);
        $this->assertNull($items[$small->id]['problem']);
        $this->assertEquals(300, $items[$small->id]['unit_price']);

        // แก้จำนวน / ลบ
        $cartId = $items[$small->id]['id'];
        $this->patchJson("/api/cart/{$cartId}", ['quantity' => 1])->assertOk();
        $this->deleteJson("/api/cart/{$cartId}")->assertOk();

        // ตะกร้าคนอื่นแก้ไม่ได้
        $other = CartItem::first();
        Sanctum::actingAs(User::factory()->create());
        $this->deleteJson("/api/cart/{$other->id}")->assertNotFound();
    }

    public function test_addresses_keep_one_default(): void
    {
        $user = User::factory()->create();

        $first = $this->address($user);
        $this->assertTrue($first->is_default);

        $second = $this->address($user);
        $this->assertFalse($second->is_default);

        $this->putJson("/api/addresses/{$second->id}", [
            ...$second->only(['recipient_name', 'phone', 'address_line', 'subdistrict', 'district', 'province', 'postcode']),
            'is_default' => true,
        ])->assertOk()->assertJsonPath('addresses.0.id', $second->id);

        $this->assertFalse($first->refresh()->is_default);

        $this->deleteJson("/api/addresses/{$second->id}")->assertOk();
        $this->assertTrue($first->refresh()->is_default);

        $this->postJson('/api/addresses', [
            'recipient_name' => 'ก',
            'phone' => '0811111111',
            'address_line' => '1',
            'subdistrict' => 'ก',
            'district' => 'ก',
            'province' => 'ไม่มีจังหวัดนี้',
            'postcode' => '123',
        ])->assertJsonValidationErrors(['province', 'postcode']);

        Sanctum::actingAs(User::factory()->create());
        $this->deleteJson("/api/addresses/{$first->id}")->assertNotFound();
    }

    public function test_checkout_two_shops_in_one_go(): void
    {
        $shopA = $this->shop();
        $shopB = $this->shop(['shipping_fee' => null]);
        $shirt = $this->product($shopA);
        $cap = $this->product($shopA, ['title' => 'หมวก', 'price' => 99, 'shipping_fee' => 60]);
        $mug = $this->product($shopB, ['title' => 'แก้ว', 'price' => 150, 'shipping_fee' => null]);
        $red = $mug->variants()->create(['name' => 'แดง', 'stock' => 4]);
        $mug->syncStockFromVariants();

        $buyer = User::factory()->create();
        $address = $this->address($buyer);

        $this->postJson('/api/cart', ['product_id' => $shirt->id, 'quantity' => 2]);
        $this->postJson('/api/cart', ['product_id' => $mug->id, 'variant_id' => $red->id]);

        $items = [
            ['product_id' => $shirt->id, 'quantity' => 2],
            ['product_id' => $cap->id, 'quantity' => 1],
            ['product_id' => $mug->id, 'variant_id' => $red->id, 'quantity' => 1],
        ];

        $preview = $this->postJson('/api/orders/preview', ['items' => $items])
            ->assertOk()
            ->assertJsonCount(2, 'groups')
            ->assertJsonPath('addresses.0.id', $address->id)
            ->json('groups');

        $groupA = collect($preview)->firstWhere('shop.id', $shopA->id);
        $shippingA = collect($groupA['delivery_methods'])->firstWhere('key', 'shipping');

        // ค่าส่งครั้งเดียวต่อร้าน ใช้ค่าส่งสูงสุด (60)
        $this->assertEquals(60, $shippingA['shipping_fee']);
        $this->assertEquals(499, $shippingA['items_total']);

        // ยอดรวม: ร้าน A 499 + 60, ร้าน B 150 + 0 (รับที่ร้าน)
        $payload = [
            'checkout_id' => 'c-123',
            'items' => $items,
            'address_id' => $address->id,
            'expected_total' => 709,
            'groups' => [
                ['shop_id' => $shopA->id, 'delivery_method' => 'shipping', 'payment_method' => 'promptpay'],
                ['shop_id' => $shopB->id, 'delivery_method' => 'storefront', 'payment_method' => 'cash', 'note' => 'เย็นนี้'],
            ],
        ];

        $orders = $this->postJson('/api/orders', $payload)
            ->assertCreated()
            ->assertJsonCount(2, 'orders')
            ->json('orders');

        $orderA = collect($orders)->firstWhere('shop.id', $shopA->id);
        $orderB = collect($orders)->firstWhere('shop.id', $shopB->id);

        $this->assertSame('709.00', number_format((float) $orderA['total'] + (float) $orderB['total'], 2, '.', ''));
        $this->assertCount(2, $orderA['items']);
        $this->assertSame(Order::STATUS_AWAITING_PAYMENT, $orderA['status']);
        $this->assertStringContainsString('50200', $orderA['address']);
        $this->assertSame('แดง', $orderB['items'][0]['variant_name']);
        $this->assertNull($orderB['address']);
        $this->assertSame(Order::STATUS_PREPARING, $orderB['status']);
        $this->assertSame('สั่งซื้อ', $orderA['history'][0]['note']);

        // จองสต็อกทั้งสินค้าและตัวเลือก
        $this->assertSame(8, $shirt->refresh()->stock);
        $this->assertSame(3, $red->refresh()->stock);
        $this->assertSame(3, $mug->refresh()->stock);

        // สั่งแล้วเอาออกจากตะกร้า
        $this->assertSame(0, CartItem::where('user_id', $buyer->id)->count());

        // กดซ้ำ checkout_id เดิม → คำสั่งซื้อเดิม ไม่สร้างใหม่
        $this->postJson('/api/orders', $payload)->assertOk()->assertJsonCount(2, 'orders');
        $this->assertSame(2, Order::count());

        // ยกเลิก → คืนสต็อกตัวเลือก
        Sanctum::actingAs($buyer);
        $this->postJson("/api/orders/{$orderB['id']}/cancel")->assertOk();
        $this->assertSame(4, $red->refresh()->stock);
        $this->assertSame(4, $mug->refresh()->stock);
    }

    public function test_checkout_rejects_changed_price_stock_and_missing_address(): void
    {
        $shop = $this->shop();
        $shirt = $this->product($shop, ['stock' => 2]);

        $buyer = User::factory()->create();
        $address = $this->address($buyer);

        $base = [
            'checkout_id' => 'c-1',
            'items' => [['product_id' => $shirt->id, 'quantity' => 1]],
            'groups' => [['shop_id' => $shop->id, 'delivery_method' => 'shipping', 'payment_method' => 'cod']],
        ];

        // ส่งพัสดุต้องมีที่อยู่
        $this->postJson('/api/orders', [...$base, 'recipient_name' => 'ก', 'recipient_phone' => '0811111111'])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'กรุณาเลือกที่อยู่จัดส่ง');

        // ราคาเปลี่ยนระหว่างดูหน้าสรุป
        $shirt->update(['price' => 250]);

        $this->postJson('/api/orders', [...$base, 'address_id' => $address->id, 'expected_total' => 240])
            ->assertStatus(409)
            ->assertJsonPath('code', 'checkout_changed')
            ->assertJsonPath('groups.0.items.0.unit_price', 250);

        // สินค้าเหลือไม่พอ
        $this->postJson('/api/orders', [
            ...$base,
            'address_id' => $address->id,
            'items' => [['product_id' => $shirt->id, 'quantity' => 3]],
        ])->assertStatus(409)->assertJsonPath('groups.0.items.0.problem', 'เหลือ 2 ชิ้น');

        // วิธีจ่ายที่ใช้ไม่ได้กับวิธีรับ
        $this->postJson('/api/orders', [
            ...$base,
            'address_id' => $address->id,
            'groups' => [['shop_id' => $shop->id, 'delivery_method' => 'shipping', 'payment_method' => 'cash']],
        ])->assertUnprocessable();

        // ที่อยู่ของคนอื่นใช้ไม่ได้
        $stranger = $this->address(User::factory()->create());
        Sanctum::actingAs($buyer);

        $this->postJson('/api/orders', [...$base, 'address_id' => $stranger->id])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'ไม่พบที่อยู่นี้ กรุณาเลือกใหม่');

        $this->assertSame(0, Order::count());
        $this->assertSame(2, $shirt->refresh()->stock);
    }
}
