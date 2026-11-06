<?php

namespace Tests\Feature;

use App\Models\Conversation;
use App\Models\Order;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use App\Models\UserBlock;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

// หน้าสินค้าแบบใหม่: ข้อมูลจัดส่ง/ร้าน/สินค้าอื่น, บันทึกสินค้า, แชทกับร้าน
class ProductPageTest extends TestCase
{
    use RefreshDatabase;

    private function seller(array $shop = []): array
    {
        $owner = User::factory()->create();

        $shop = Shop::create([
            'user_id' => $owner->id,
            'name' => 'ร้านสวน ' . $owner->id,
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => Shop::STATUS_ACTIVE,
            'delivery_methods' => ['shipping', 'storefront'],
            'ship_within_days' => 2,
            'payment_methods' => ['cod', 'cash'],
            ...$shop,
        ]);

        return [$owner, $shop];
    }

    private function product(Shop $shop, array $fields = []): Product
    {
        return $shop->products()->create([
            'title' => 'มะม่วง',
            'price' => 100,
            'stock' => 5,
            'shipping_fee' => 40,
            'category' => 'produce',
            'status' => Product::STATUS_ACTIVE,
            ...$fields,
        ]);
    }

    public function test_product_page_shows_shipping_shop_and_other_products(): void
    {
        [, $shop] = $this->seller();
        $product = $this->product($shop);
        $other = $this->product($shop, ['title' => 'ทุเรียน']);
        $this->product($shop, ['title' => 'ซ่อนไว้', 'status' => Product::STATUS_HIDDEN]);

        // ขายแล้ว 3 ชิ้น ส่งเฉลี่ย 24 ชม. (ใช้ข้อมูลจริงจากคำสั่งซื้อ)
        $buyer = User::factory()->create();

        foreach ([20, 24, 28] as $hours) {
            Order::create([
                'code' => 'OR' . $hours,
                'buyer_id' => $buyer->id,
                'shop_id' => $shop->id,
                'product_id' => $product->id,
                'product_title' => $product->title,
                'unit_price' => 100,
                'quantity' => 1,
                'total' => 140,
                'delivery_method' => 'shipping',
                'payment_method' => 'cod',
                'recipient_name' => 'ก',
                'recipient_phone' => '0811111111',
                'status' => Order::STATUS_COMPLETED,
                'shipped_at' => now()->subDays(2)->addHours($hours),
            ])->forceFill(['created_at' => now()->subDays(2)])->save();
        }

        Sanctum::actingAs(User::factory()->create());

        $response = $this->getJson("/api/market/products/{$product->id}")
            ->assertOk()
            ->assertJsonPath('product.sold_count', 3)
            ->assertJsonPath('product.is_saved', false)
            ->assertJsonPath('shop.ship_within_days', 2)
            ->assertJsonPath('shop.stats.sold_count', 3)
            ->assertJsonPath('shop.stats.avg_ship_hours', 24)
            ->assertJsonPath('shop.products_count', 2)
            ->assertJsonCount(1, 'other_products')
            ->assertJsonPath('other_products.0.id', $other->id);

        $options = collect($response->json('product.delivery_options'))->keyBy('key');

        $this->assertEquals(40, $options['shipping']['shipping_fee']);
        $this->assertEquals(0, $options['storefront']['shipping_fee']);
    }

    public function test_save_and_list_saved_products(): void
    {
        [, $shop] = $this->seller();
        $product = $this->product($shop);
        $user = User::factory()->create();

        Sanctum::actingAs($user);

        $this->postJson("/api/market/products/{$product->id}/save")->assertOk()->assertJsonPath('is_saved', true);
        $this->postJson("/api/market/products/{$product->id}/save")->assertOk();

        $this->getJson("/api/market/products/{$product->id}")->assertJsonPath('product.is_saved', true);

        $this->getJson('/api/market/saved-products')
            ->assertOk()
            ->assertJsonCount(1, 'products')
            ->assertJsonPath('products.0.id', $product->id);

        // สินค้าที่ถูกซ่อนไม่แสดงในรายการที่บันทึก
        $product->update(['status' => Product::STATUS_HIDDEN]);
        $this->getJson('/api/market/saved-products')->assertJsonCount(0, 'products');

        $this->deleteJson("/api/market/products/{$product->id}/save")->assertOk()->assertJsonPath('is_saved', false);
    }

    public function test_customer_can_chat_with_a_shop_outside_their_group(): void
    {
        [$owner, $shop] = $this->seller();
        $customer = User::factory()->create();

        Sanctum::actingAs($customer);

        $id = $this->postJson('/api/chats', ['shop_id' => $shop->id])
            ->assertOk()
            ->assertJsonPath('conversation.can_send', true)
            // ลูกค้าเห็นห้องเป็นชื่อร้าน
            ->assertJsonPath('conversation.user.name', $shop->name)
            ->assertJsonPath('conversation.shop.id', $shop->id)
            ->json('conversation.id');

        $this->postJson("/api/chats/{$id}/messages", ['body' => 'มะม่วงยังมีไหมคะ'])->assertCreated();

        // เจ้าของร้านตอบกลับได้ และเห็นชื่อลูกค้า
        Sanctum::actingAs($owner);

        $this->getJson('/api/chats')
            ->assertOk()
            ->assertJsonPath('conversations.0.user.name', $customer->name)
            ->assertJsonPath('conversations.0.shop.is_mine', true)
            ->assertJsonPath('conversations.0.can_send', true);

        $this->postJson("/api/chats/{$id}/messages", ['body' => 'ยังมีค่ะ'])->assertCreated();

        // ทักร้านซ้ำ = ห้องเดิม
        Sanctum::actingAs($customer);
        $this->postJson('/api/chats', ['shop_id' => $shop->id])->assertJsonPath('conversation.id', $id);

        $this->assertSame(1, Conversation::count());
    }

    public function test_shop_chat_rules(): void
    {
        [$owner, $shop] = $this->seller();
        $customer = User::factory()->create();

        // ทักร้านตัวเองไม่ได้
        Sanctum::actingAs($owner);
        $this->postJson('/api/chats', ['shop_id' => $shop->id])->assertUnprocessable();

        // ห้องแชทธรรมดากับคนนอกกลุ่ม ยังส่งไม่ได้
        Sanctum::actingAs($customer);
        $this->postJson('/api/chats', ['user_id' => $owner->id])->assertForbidden();

        // บล็อกกันแล้วทักไม่ได้ / ส่งไม่ได้
        $id = $this->postJson('/api/chats', ['shop_id' => $shop->id])->json('conversation.id');

        UserBlock::create(['user_id' => $owner->id, 'blocked_user_id' => $customer->id]);

        $this->postJson("/api/chats/{$id}/messages", ['body' => 'สวัสดี'])->assertForbidden();
        $this->postJson('/api/chats', ['shop_id' => $shop->id])->assertForbidden();

        // ร้านที่ปิด ทักใหม่ไม่ได้
        [, $closed] = $this->seller(['status' => Shop::STATUS_SUSPENDED]);
        $this->postJson('/api/chats', ['shop_id' => $closed->id])->assertNotFound();
    }

    public function test_seller_sets_ship_within_days(): void
    {
        [$owner, $shop] = $this->seller();

        Sanctum::actingAs($owner);

        $base = [
            'name' => $shop->name,
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
        ];

        $this->postJson('/api/my-shop/update', [...$base, 'ship_within_days' => 3])
            ->assertOk()
            ->assertJsonPath('shop.ship_within_days', 3);

        // แอปเวอร์ชันเก่าไม่ส่ง → ไม่เปลี่ยน
        $this->postJson('/api/my-shop/update', $base)->assertOk();
        $this->assertSame(3, $shop->refresh()->ship_within_days);

        $this->postJson('/api/my-shop/update', [...$base, 'ship_within_days' => 99])
            ->assertJsonValidationErrors('ship_within_days');
    }
}
