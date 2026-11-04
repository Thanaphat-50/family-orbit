<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Shop;
use App\Models\ShopPromotion;
use App\Models\User;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

// ช่องร้านแนะนำแบบชำระเงิน (แบนเนอร์ใหญ่ ราคาแพงกว่าช่องสินค้า)
class ShopPromotionTest extends TestCase
{
    use FakesImages, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());

        config([
            'market.promptpay_id' => '0812345678',
            'market.featured_slots' => 10,
        ]);
    }

    private function seller(string $status = Shop::STATUS_ACTIVE): array
    {
        $owner = User::factory()->create();

        $shop = Shop::create([
            'user_id' => $owner->id,
            'name' => 'ร้าน ' . $owner->id,
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => $status,
            'terms_accepted_at' => now(),
        ]);

        return [$owner, $shop];
    }

    private function paidOrder(User $owner, string $plan = 'day'): ShopPromotion
    {
        Sanctum::actingAs($owner);

        $id = $this->postJson('/api/my-shop/promotion', ['plan' => $plan])->assertCreated()->json('order.id');

        $this->post("/api/my-shop/shop-promotions/{$id}/slip", [
            'slip' => $this->fakePng('slip.png'),
        ], ['Accept' => 'application/json'])->assertOk();

        return ShopPromotion::findOrFail($id);
    }

    public function test_shop_slot_costs_more_than_product_slot(): void
    {
        [$owner] = $this->seller();

        Sanctum::actingAs($owner);

        $plans = collect($this->getJson('/api/my-shop/promotion')
            ->assertOk()
            ->assertJsonPath('payment_enabled', true)
            ->assertJsonPath('slot_label', 'ช่องร้านแนะนำ')
            ->json('plans'))->keyBy('key');

        foreach (config('market.promotion_plans') as $key => $productPlan) {
            $this->assertGreaterThan($productPlan['price'], $plans[$key]['price']);
        }
    }

    public function test_full_flow_puts_the_shop_in_the_banner(): void
    {
        [$owner, $shop] = $this->seller();

        Sanctum::actingAs($owner);

        $response = $this->postJson('/api/my-shop/promotion', ['plan' => 'day'])
            ->assertCreated()
            ->assertJsonPath('order.amount', '149.00')
            ->assertJsonPath('order.shop_name', $shop->name);

        $this->assertStringContainsString('5406149.00', $response->json('order.payment.promptpay_payload'));

        // รายการค้างอยู่ → สั่งซ้ำไม่ได้
        $this->postJson('/api/my-shop/promotion', ['plan' => 'month'])->assertConflict();

        $id = $response->json('order.id');

        $this->post("/api/my-shop/shop-promotions/{$id}/slip", [
            'slip' => $this->fakePng('slip.png'),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('order.status', ShopPromotion::STATUS_PENDING_REVIEW);

        ShopPromotion::findOrFail($id)->approve(User::factory()->create(['is_admin' => true]));

        $this->assertTrue($shop->refresh()->isFeatured());
        $this->assertTrue(AppNotification::where('user_id', $owner->id)->where('type', 'promotion_status')->exists());

        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/market/featured')
            ->assertOk()
            ->assertJsonCount(1, 'shops')
            ->assertJsonPath('shops.0.id', $shop->id);
    }

    public function test_renewal_and_slot_limit(): void
    {
        config(['market.featured_slots' => 1]);

        $admin = User::factory()->create(['is_admin' => true]);

        [$ownerA, $shopA] = $this->seller();
        [$ownerB] = $this->seller();

        $this->paidOrder($ownerA, 'day')->approve($admin);

        $firstEnd = $shopA->refresh()->featured_until->copy();

        // ร้านอื่นซื้อไม่ได้เมื่อช่องเต็ม
        Sanctum::actingAs($ownerB);

        $this->getJson('/api/my-shop/promotion')->assertJsonPath('slots.available', false);
        $this->postJson('/api/my-shop/promotion', ['plan' => 'day'])->assertConflict();

        // ร้านเดิมต่ออายุได้ นับต่อจากวันหมดเดิม
        $this->paidOrder($ownerA, 'month')->approve($admin);

        $this->assertEqualsWithDelta($firstEnd->addDays(30)->timestamp, $shopA->refresh()->featured_until->timestamp, 5);
    }

    public function test_only_the_owner_can_pay_and_closed_shops_cannot_buy(): void
    {
        [$owner] = $this->seller();

        Sanctum::actingAs($owner);

        $id = $this->postJson('/api/my-shop/promotion', ['plan' => 'day'])->json('order.id');

        Sanctum::actingAs(User::factory()->create());

        $this->post("/api/my-shop/shop-promotions/{$id}/slip", [
            'slip' => $this->fakePng('slip.png'),
        ], ['Accept' => 'application/json'])->assertNotFound();

        [$suspendedOwner] = $this->seller(Shop::STATUS_SUSPENDED);

        Sanctum::actingAs($suspendedOwner);

        $this->postJson('/api/my-shop/promotion', ['plan' => 'day'])->assertUnprocessable();
    }

    public function test_deleting_the_shop_removes_slips(): void
    {
        [$owner, $shop] = $this->seller();

        $this->paidOrder($owner);

        $shop->refresh()->delete();

        $this->assertCount(0, Storage::disk(MediaStorage::disk())->allFiles('promotion_slips'));
        $this->assertSame(0, ShopPromotion::count());
    }
}
