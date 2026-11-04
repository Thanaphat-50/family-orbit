<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Product;
use App\Models\Shop;
use App\Models\ShopReport;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

// รายงานร้านค้า/สินค้า → แจ้งผู้ดูแล / ถูกรายงานหลายคน → ปิดร้านชั่วคราว
class ShopReportTest extends TestCase
{
    use RefreshDatabase;

    private function shop(): Shop
    {
        return Shop::create([
            'user_id' => User::factory()->create()->id,
            'name' => 'ร้านป้าแดง',
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => Shop::STATUS_ACTIVE,
            'terms_accepted_at' => now(),
        ]);
    }

    private function reportShop(Shop $shop, string $reason = 'scam', ?string $details = null): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson("/api/market/shops/{$shop->id}/report", [
            'reason' => $reason,
            'details' => $details,
        ])->assertOk();
    }

    public function test_shop_report_notifies_admins_with_reason_and_details(): void
    {
        $admin = User::factory()->create(['is_admin' => true]);

        $shop = $this->shop();

        $this->reportShop($shop, 'scam', 'โอนเงินแล้วไม่ส่งของ');

        $notification = AppNotification::where('user_id', $admin->id)->where('type', 'market_report')->sole();

        $this->assertSame('มีผู้รายงานร้านค้า', $notification->title);
        $this->assertStringContainsString('หลอกลวง / โกง', $notification->message);
        $this->assertStringContainsString('โอนเงินแล้วไม่ส่งของ', $notification->message);
        $this->assertSame($shop->id, $notification->data['shop_id']);

        // คนเดิมรายงานซ้ำ → ไม่นับเพิ่ม ไม่แจ้งซ้ำ
        $this->postJson("/api/market/shops/{$shop->id}/report", ['reason' => 'spam'])->assertOk();

        $this->assertSame(1, ShopReport::count());
        $this->assertSame(1, AppNotification::where('type', 'market_report')->count());
    }

    public function test_many_reports_suspend_the_shop_until_review(): void
    {
        config(['market.auto_suspend_shop_reports' => 3]);

        User::factory()->create(['is_admin' => true]);

        $shop = $this->shop();

        $this->reportShop($shop);
        $this->reportShop($shop);

        $this->assertSame(Shop::STATUS_ACTIVE, $shop->refresh()->status);

        $this->reportShop($shop);

        $shop->refresh();

        $this->assertSame(Shop::STATUS_SUSPENDED, $shop->status);
        $this->assertSame(Shop::AUTO_REPORT_REASON, $shop->status_reason);

        // เจ้าของร้านรู้ว่าร้านถูกปิดชั่วคราว / ผู้ซื้อเปิดร้านไม่ได้แล้ว
        $this->assertTrue(
            AppNotification::where('user_id', $shop->user_id)->where('type', 'shop_status')->exists()
        );

        $this->getJson("/api/market/shops/{$shop->id}")->assertNotFound();

        $this->assertStringContainsString(
            'ปิดร้านชั่วคราวแล้ว',
            AppNotification::where('type', 'market_report')->latest('id')->first()->message
        );
    }

    public function test_product_report_notifies_admins(): void
    {
        $admin = User::factory()->create(['is_admin' => true]);

        $product = Product::create([
            'shop_id' => $this->shop()->id,
            'title' => 'มะม่วงน้ำดอกไม้',
            'price' => 60,
            'category' => 'produce',
            'status' => Product::STATUS_ACTIVE,
        ]);

        Sanctum::actingAs(User::factory()->create());

        $this->postJson("/api/market/products/{$product->id}/report", ['reason' => 'fake'])->assertOk();

        $notification = AppNotification::where('user_id', $admin->id)->where('type', 'market_report')->sole();

        $this->assertSame('มีผู้รายงานสินค้า', $notification->title);
        $this->assertStringContainsString('มะม่วงน้ำดอกไม้', $notification->message);
        $this->assertSame($product->id, $notification->data['product_id']);
    }
}
