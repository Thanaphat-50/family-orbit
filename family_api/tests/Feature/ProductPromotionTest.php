<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Product;
use App\Models\ProductPromotion;
use App\Models\Shop;
use App\Models\User;
use App\Support\MediaStorage;
use App\Support\PromptPay;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

// ช่องแนะนำสินค้าแบบชำระเงิน: แพ็กเกจ → QR พร้อมเพย์ → แนบสลิป → Admin อนุมัติ
class ProductPromotionTest extends TestCase
{
    use FakesImages, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());

        config([
            'market.promptpay_id' => '0812345678',
            'market.promptpay_name' => 'บริษัท ทดสอบ',
            'market.featured_slots_per_category' => 10,
            'market.promotion_payment_hours' => 24,
        ]);
    }

    private function sellerWithProduct(string $category = 'produce', string $shopStatus = Shop::STATUS_ACTIVE): array
    {
        $owner = User::factory()->create();

        $shop = Shop::create([
            'user_id' => $owner->id,
            'name' => 'ร้าน ' . $owner->id,
            'category' => $category,
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => $shopStatus,
            'terms_accepted_at' => now(),
        ]);

        $product = Product::create([
            'shop_id' => $shop->id,
            'title' => 'สินค้า ' . $owner->id,
            'price' => 100,
            'category' => $category,
            'status' => Product::STATUS_ACTIVE,
        ]);

        return [$owner, $product];
    }

    private function admin(): User
    {
        return User::factory()->create(['is_admin' => true]);
    }

    private function order(User $owner, Product $product, string $plan = 'day'): ProductPromotion
    {
        Sanctum::actingAs($owner);

        $id = $this->postJson("/api/my-shop/products/{$product->id}/promotion", ['plan' => $plan])
            ->assertCreated()
            ->json('order.id');

        return ProductPromotion::findOrFail($id);
    }

    private function paidOrder(User $owner, Product $product, string $plan = 'day'): ProductPromotion
    {
        $order = $this->order($owner, $product, $plan);

        $this->post("/api/my-shop/promotions/{$order->id}/slip", [
            'slip' => $this->fakePng('slip.png'),
        ], ['Accept' => 'application/json'])->assertOk();

        return $order->refresh();
    }

    // =====================================================
    // QR พร้อมเพย์
    // =====================================================

    public function test_promptpay_payload_follows_the_standard(): void
    {
        // ค่ามาตรฐานของ CRC-16/CCITT-FALSE
        $this->assertSame('29B1', PromptPay::crc16('123456789'));

        $payload = PromptPay::payload('081-234-5678', 59);

        $this->assertStringStartsWith('000201010212', $payload);
        $this->assertStringContainsString('29370016A00000067701011101130066812345678', $payload);
        $this->assertStringContainsString('540559.00', $payload);
        $this->assertStringContainsString('5802TH', $payload);
        $this->assertSame(PromptPay::crc16(substr($payload, 0, -4)), substr($payload, -4));

        $this->assertStringContainsString('0213' . '1234567890123', PromptPay::payload('1234567890123', 10));

        $this->assertSame('081xxx5678', PromptPay::maskedId('0812345678'));
        $this->assertFalse(PromptPay::isValidId('12345'));
    }

    // =====================================================
    // ยังไม่ตั้งบัญชีรับเงิน → ซื้อไม่ได้
    // =====================================================

    public function test_buying_is_closed_without_a_promptpay_account(): void
    {
        config(['market.promptpay_id' => null]);

        [$owner, $product] = $this->sellerWithProduct();

        Sanctum::actingAs($owner);

        $this->getJson("/api/my-shop/products/{$product->id}/promotion")
            ->assertOk()
            ->assertJsonPath('payment_enabled', false)
            ->assertJsonCount(3, 'plans');

        $this->postJson("/api/my-shop/products/{$product->id}/promotion", ['plan' => 'day'])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'ยังไม่เปิดรับชำระเงินค่าช่องแนะนำ');
    }

    // =====================================================
    // สั่งซื้อ → แนบสลิป → อนุมัติ → ขึ้นช่องแนะนำ
    // =====================================================

    public function test_full_flow_from_order_to_featured_listing(): void
    {
        [$owner, $product] = $this->sellerWithProduct();

        Sanctum::actingAs($owner);

        $response = $this->postJson("/api/my-shop/products/{$product->id}/promotion", ['plan' => 'day'])
            ->assertCreated()
            ->assertJsonPath('order.status', ProductPromotion::STATUS_AWAITING_PAYMENT)
            ->assertJsonPath('order.amount', '59.00')
            ->assertJsonPath('order.payment.promptpay_id', '081xxx5678')
            ->assertJsonPath('order.payment.promptpay_name', 'บริษัท ทดสอบ');

        $this->assertStringContainsString('540559.00', $response->json('order.payment.promptpay_payload'));

        // มีรายการค้างอยู่ → สั่งซ้ำไม่ได้
        $this->postJson("/api/my-shop/products/{$product->id}/promotion", ['plan' => 'month'])
            ->assertConflict();

        $orderId = $response->json('order.id');

        $this->post("/api/my-shop/promotions/{$orderId}/slip", [
            'slip' => $this->fakePng('slip.png'),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('order.status', ProductPromotion::STATUS_PENDING_REVIEW)
            ->assertJsonPath('order.has_slip', true)
            ->assertJsonMissingPath('order.payment')
            ->assertJsonMissingPath('order.slip_path');

        $this->assertCount(1, Storage::disk(MediaStorage::disk())->allFiles('promotion_slips'));

        ProductPromotion::findOrFail($orderId)->approve($this->admin());

        $product->refresh();

        $this->assertTrue($product->isFeatured());
        $this->assertEqualsWithDelta(now()->addDay()->timestamp, $product->featured_until->timestamp, 5);
        $this->assertTrue(AppNotification::where('user_id', $owner->id)->where('type', 'promotion_status')->exists());

        // ผู้ซื้อเห็นในช่องแนะนำทั้งหมด และในหมวดของสินค้า
        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/market/featured-products')
            ->assertOk()
            ->assertJsonCount(1, 'products')
            ->assertJsonPath('products.0.id', $product->id)
            ->assertJsonPath('products.0.is_featured', true);

        $this->getJson('/api/market/featured-products?category=produce')->assertJsonCount(1, 'products');
        $this->getJson('/api/market/featured-products?category=food')->assertJsonCount(0, 'products');

        // หมดเวลา → ไม่แสดงในช่องแนะนำแล้ว
        $this->travel(2)->days();

        $this->getJson('/api/market/featured-products')->assertJsonCount(0, 'products');
    }

    public function test_renewing_continues_from_the_current_end(): void
    {
        [$owner, $product] = $this->sellerWithProduct();

        $this->paidOrder($owner, $product, 'day')->approve($this->admin());

        $firstEnd = $product->refresh()->featured_until->copy();

        $this->paidOrder($owner, $product, 'month')->approve($this->admin());

        $this->assertEqualsWithDelta($firstEnd->addDays(30)->timestamp, $product->refresh()->featured_until->timestamp, 5);
    }

    // =====================================================
    // ช่องจำกัดต่อหมวด
    // =====================================================

    public function test_slots_are_limited_per_category(): void
    {
        config(['market.featured_slots_per_category' => 1]);

        [$ownerA, $productA] = $this->sellerWithProduct('produce');
        [$ownerB, $productB] = $this->sellerWithProduct('produce');
        [$ownerC, $productC] = $this->sellerWithProduct('food');

        // A จองช่องไว้ (รอชำระ) → B ในหมวดเดียวกันซื้อไม่ได้
        $orderA = $this->order($ownerA, $productA);

        Sanctum::actingAs($ownerB);

        $this->getJson("/api/my-shop/products/{$productB->id}/promotion")
            ->assertOk()
            ->assertJsonPath('slots.used', 1)
            ->assertJsonPath('slots.available', false);

        $this->postJson("/api/my-shop/products/{$productB->id}/promotion", ['plan' => 'day'])
            ->assertConflict();

        // หมวดอื่นยังว่าง
        $this->order($ownerC, $productC);

        // A ยกเลิก → ช่องว่าง B ซื้อได้
        Sanctum::actingAs($ownerA);

        $this->postJson("/api/my-shop/promotions/{$orderA->id}/cancel")
            ->assertOk()
            ->assertJsonPath('order.status', ProductPromotion::STATUS_CANCELLED);

        $this->order($ownerB, $productB);
    }

    public function test_unpaid_orders_expire_and_free_the_slot(): void
    {
        config(['market.featured_slots_per_category' => 1]);

        [$ownerA, $productA] = $this->sellerWithProduct();
        [$ownerB, $productB] = $this->sellerWithProduct();

        $order = $this->order($ownerA, $productA);

        $this->travel(25)->hours();

        Sanctum::actingAs($ownerA);

        $this->post("/api/my-shop/promotions/{$order->id}/slip", [
            'slip' => $this->fakePng('slip.png'),
        ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'หมดเวลาแนบสลิปแล้ว กรุณาสั่งซื้อใหม่');

        $this->assertSame(ProductPromotion::STATUS_CANCELLED, $order->refresh()->status);

        $this->order($ownerB, $productB);
    }

    // =====================================================
    // สิทธิ์ / สถานะที่ซื้อไม่ได้ / ไม่ผ่าน
    // =====================================================

    public function test_only_the_seller_can_pay_and_hidden_products_cannot_be_promoted(): void
    {
        [$owner, $product] = $this->sellerWithProduct();

        $order = $this->order($owner, $product);

        Sanctum::actingAs(User::factory()->create());

        $this->post("/api/my-shop/promotions/{$order->id}/slip", [
            'slip' => $this->fakePng('slip.png'),
        ], ['Accept' => 'application/json'])->assertNotFound();

        $this->postJson("/api/my-shop/products/{$product->id}/promotion", ['plan' => 'day'])->assertNotFound();

        [$owner2, $hidden] = $this->sellerWithProduct();
        $hidden->update(['status' => Product::STATUS_HIDDEN]);

        Sanctum::actingAs($owner2);

        $this->postJson("/api/my-shop/products/{$hidden->id}/promotion", ['plan' => 'day'])->assertUnprocessable();

        [$owner3, $pendingShopProduct] = $this->sellerWithProduct('produce', Shop::STATUS_PENDING);

        Sanctum::actingAs($owner3);

        $this->postJson("/api/my-shop/products/{$pendingShopProduct->id}/promotion", ['plan' => 'day'])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'ร้านต้องเปิดขายอยู่ จึงจะซื้อช่องแนะนำได้');
    }

    public function test_rejected_slip_does_not_feature_the_product(): void
    {
        [$owner, $product] = $this->sellerWithProduct();

        $order = $this->paidOrder($owner, $product);

        $order->reject($this->admin(), 'ยอดเงินไม่ตรง');

        $this->assertSame(ProductPromotion::STATUS_REJECTED, $order->refresh()->status);
        $this->assertFalse($product->refresh()->isFeatured());

        Sanctum::actingAs($owner);

        $this->getJson('/api/my-shop/promotions')
            ->assertOk()
            ->assertJsonPath('orders.0.status', ProductPromotion::STATUS_REJECTED)
            ->assertJsonPath('orders.0.reject_reason', 'ยอดเงินไม่ตรง');

        // ไม่ผ่านแล้วซื้อใหม่ได้
        $this->order($owner, $product);
    }

    public function test_deleting_a_product_removes_its_slips(): void
    {
        [$owner, $product] = $this->sellerWithProduct();

        $this->paidOrder($owner, $product);

        $product->delete();

        $this->assertCount(0, Storage::disk(MediaStorage::disk())->allFiles('promotion_slips'));
        $this->assertSame(0, ProductPromotion::count());
    }
}
