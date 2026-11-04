<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\MarketFlag;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use App\Services\MarketScreening;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

// ร้านเปิดขายได้ทันที + ตรวจสินค้าต้องห้ามอัตโนมัติ → ซ่อนไว้ก่อน + แจ้งผู้ดูแล
class MarketScreeningTest extends TestCase
{
    use FakesImages, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());
    }

    private function admin(): User
    {
        return User::factory()->create(['is_admin' => true]);
    }

    private function activeShop(?User $owner = null, string $name = 'ร้านป้าแดง'): Shop
    {
        return Shop::create([
            'user_id' => ($owner ?? User::factory()->create())->id,
            'name' => $name,
            'category' => 'other',
            'phone' => '0812345678',
            'province' => 'สุราษฎร์ธานี',
            'status' => Shop::STATUS_ACTIVE,
            'terms_accepted_at' => now(),
        ]);
    }

    private function postProduct(User $owner, string $title, string $description = ''): void
    {
        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop/products', [
            'title' => $title,
            'description' => $description,
            'price' => '100',
            'category' => 'other',
            'images' => [$this->fakePng()],
        ])->assertCreated();
    }

    // =====================================================
    // เปิดร้าน → ขายได้ทันที ไม่ต้องรอผู้ดูแล
    // =====================================================

    public function test_new_shop_opens_immediately_and_products_show_in_the_market(): void
    {
        $owner = User::factory()->create();

        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop', [
            'name' => 'ร้านผักป้าแดง',
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'accept_terms' => '1',
        ])
            ->assertCreated()
            ->assertJsonPath('shop.status', Shop::STATUS_ACTIVE)
            ->assertJsonPath('message', 'เปิดร้านแล้ว ลงสินค้าได้เลย');

        $this->assertNotNull(Shop::first()->approved_at);

        $this->postProduct($owner, 'ผักกาดหอม', 'ปลูกเอง');

        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/market/products')
            ->assertOk()
            ->assertJsonPath('products.0.title', 'ผักกาดหอม');

        $this->assertSame(0, MarketFlag::count());
    }

    // =====================================================
    // สินค้าต้องห้าม → รายการตรวจพบ + แจ้งผู้ดูแลทุกคน
    // =====================================================

    public function test_prohibited_product_is_flagged_and_admins_are_notified(): void
    {
        $adminA = $this->admin();
        $adminB = $this->admin();

        $owner = User::factory()->create();
        $this->activeShop($owner);

        // เขียนแยกเพื่อเลี่ยงคำ ก็ยังตรวจเจอ
        $this->postProduct($owner, 'น้ำยา บุ-หรี่ ไฟฟ้า', 'กลิ่นมิ้นท์ ส่งไว');

        $flag = MarketFlag::sole();

        $this->assertSame(Product::class, $flag->flaggable_type);
        $this->assertSame(['tobacco'], $flag->categories);
        $this->assertContains('บุหรี่', $flag->terms);
        $this->assertSame(MarketFlag::STATUS_OPEN, $flag->status);
        $this->assertTrue($flag->auto_hidden);

        foreach ([$adminA, $adminB] as $admin) {
            $notification = AppNotification::where('user_id', $admin->id)->where('type', 'market_flag')->sole();

            $this->assertSame('ตรวจพบสินค้าที่อาจผิดกฎหมาย', $notification->title);
            $this->assertStringContainsString('บุหรี่ / บุหรี่ไฟฟ้า', $notification->message);
            $this->assertStringContainsString('ซ่อนสินค้าไว้แล้ว', $notification->message);
        }

        // สินค้าถูกซ่อนทันที ผู้ซื้อมองไม่เห็น / เจ้าของร้านได้รับแจ้งว่าถูกซ่อนชั่วคราว
        $this->assertNotNull(Product::sole()->hidden_at);
        $this->assertSame(0, AppNotification::where('user_id', $owner->id)->where('type', 'market_flag')->count());
        $this->assertSame(
            'สินค้าถูกซ่อนชั่วคราว',
            AppNotification::where('user_id', $owner->id)->where('type', 'shop_status')->sole()->title
        );

        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/market/products')->assertOk()->assertJsonCount(0, 'products');
    }

    public function test_seller_sees_why_a_new_product_is_hidden(): void
    {
        $owner = User::factory()->create();
        $this->activeShop($owner);

        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop/products', [
            'title' => 'งาช้างแท้',
            'price' => '100',
            'category' => 'other',
            'images' => [$this->fakePng()],
        ])
            ->assertCreated()
            ->assertJsonPath('message', 'เพิ่มสินค้าแล้ว แต่ระบบพบคำที่อาจผิดกฎ สินค้าถูกซ่อนไว้รอทีมงานตรวจสอบ');

        $this->assertNotNull(Product::sole()->hidden_at);
    }

    public function test_harmless_phrases_and_place_names_are_not_flagged(): void
    {
        $screening = app(MarketScreening::class);

        $this->assertNull($screening->match('ปืนฉีดน้ำสำหรับเด็ก', 'ตลับลูกปืนรถจักรยาน'));
        $this->assertNull($screening->match('เจลแอลกอฮอล์ล้างมือ', 'ส่งจากสุราษฎร์ธานี'));
        $this->assertNull($screening->match('ไม่ใช่ของปลอม ของแท้ 100%'));
        $this->assertNull($screening->match('ผักกาดหอม', 'กลิ่นหอม ปลูกเอง'));

        $this->assertSame(['weapons'], $screening->match('ปืนอัดลม BB gun')['categories']);
        $this->assertSame(['alcohol'], $screening->match('เหล้าบ๊วยทำเอง')['categories']);
        $this->assertSame(['medicine'], $screening->match('ยาลดน้ำหนัก ไม่มี อย.')['categories']);
    }

    public function test_shop_names_are_screened_too(): void
    {
        $this->admin();

        $owner = User::factory()->create();

        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop', [
            'name' => 'ร้านบาคาร่าออนไลน์',
            'category' => 'other',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'accept_terms' => '1',
        ])
            ->assertCreated()
            ->assertJsonPath('shop.status', Shop::STATUS_SUSPENDED)
            ->assertJsonPath('message', Shop::AUTO_SCREEN_REASON);

        $flag = MarketFlag::sole();

        $this->assertSame(Shop::class, $flag->flaggable_type);
        $this->assertSame(['gambling'], $flag->categories);
        $this->assertTrue($flag->auto_hidden);

        // ผู้ดูแลตรวจแล้วไม่ผิดกฎ → เปิดร้านคืน
        $flag->dismiss(User::where('is_admin', true)->first());

        $this->assertSame(Shop::STATUS_ACTIVE, Shop::sole()->status);
    }

    // =====================================================
    // ไม่แจ้งซ้ำ: แก้ราคา / คำเดิมที่ผู้ดูแลตรวจแล้ว
    // =====================================================

    public function test_same_words_are_not_reported_again_after_review(): void
    {
        $admin = $this->admin();

        $owner = User::factory()->create();
        $shop = $this->activeShop($owner);

        $product = Product::create([
            'shop_id' => $shop->id,
            'title' => 'แก้วเบียร์ทรงสูง เบียร์สด',
            'price' => 100,
            'category' => 'other',
            'status' => Product::STATUS_ACTIVE,
        ]);

        $flag = MarketFlag::sole();

        $this->assertNotNull($product->refresh()->hidden_at);

        // ไม่ผิดกฎ (แก้วเบียร์) → แสดงคืน + แจ้งเจ้าของร้าน
        $flag->dismiss($admin);

        $this->assertNull($product->refresh()->hidden_at);
        $this->assertTrue(
            AppNotification::where('user_id', $owner->id)->where('title', 'สินค้าแสดงตามปกติแล้ว')->exists()
        );

        // แก้ราคา → ไม่ตรวจใหม่ / แก้รายละเอียดแต่คำต้องห้ามเหมือนเดิม → ไม่แจ้งซ้ำ ไม่ซ่อนซ้ำ
        $product->update(['price' => 120]);
        $product->update(['description' => 'มีหลายขนาด']);

        $this->assertSame(1, MarketFlag::count());
        $this->assertSame(1, AppNotification::where('type', 'market_flag')->count());
        $this->assertNull($product->refresh()->hidden_at);

        // เพิ่มคำต้องห้ามใหม่ → ซ่อน + แจ้งอีกครั้ง
        $product->update(['description' => 'แถมบุหรี่']);

        $this->assertNotNull($product->refresh()->hidden_at);
        $this->assertSame(2, MarketFlag::count());
        $this->assertSame(MarketFlag::STATUS_OPEN, MarketFlag::latest('id')->first()->status);
        $this->assertSame(2, AppNotification::where('type', 'market_flag')->count());
    }

    public function test_deleting_a_product_removes_its_flags(): void
    {
        $shop = $this->activeShop();

        $product = Product::create([
            'shop_id' => $shop->id,
            'title' => 'งาช้างแกะสลัก',
            'category' => 'other',
            'status' => Product::STATUS_ACTIVE,
        ]);

        $this->assertSame(1, MarketFlag::count());

        $product->delete();

        $this->assertSame(0, MarketFlag::count());
    }
}
