<?php

namespace Tests\Feature;

use App\Filament\Resources\Products\Pages\ListProducts;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use App\Support\MediaStorage;
use Filament\Actions\Testing\TestAction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use Tests\TestCase;

class MarketTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());
    }

    private function shop(
        string $name = 'ร้านป้าแดง',
        string $status = Shop::STATUS_ACTIVE,
        string $province = 'เชียงใหม่',
        ?User $owner = null
    ): Shop {
        return Shop::create([
            'user_id' => ($owner ?? User::factory()->create())->id,
            'name' => $name,
            'category' => 'produce',
            'phone' => '0812345678',
            'line_id' => '@shop',
            'province' => $province,
            'status' => $status,
            'approved_at' => $status === Shop::STATUS_ACTIVE ? now() : null,
            'terms_accepted_at' => now(),
        ]);
    }

    private function product(Shop $shop, string $title, array $overrides = []): Product
    {
        $product = $shop->products()->create([
            'title' => $title,
            'price' => 35,
            'category' => 'produce',
            'status' => Product::STATUS_ACTIVE,
            ...$overrides,
        ]);

        $product->images()->create(['path' => "product_images/{$product->id}.png", 'sort' => 0]);

        return $product;
    }

    private function titles($response): array
    {
        return collect($response->json('products'))->pluck('title')->sort()->values()->all();
    }

    // =====================================================
    // ตลาดแสดงเฉพาะสินค้าที่ควรเห็น
    // =====================================================

    public function test_market_lists_only_visible_products(): void
    {
        $open = $this->shop();
        $this->product($open, 'ผักกาด');
        $this->product($open, 'ซ่อนโดยร้าน', ['status' => Product::STATUS_HIDDEN]);
        $this->product($open, 'ซ่อนโดยแอดมิน', ['hidden_at' => now()]);

        $this->product($this->shop('ร้านรอตรวจ', Shop::STATUS_PENDING), 'ของร้านรอตรวจ');
        $this->product($this->shop('ร้านถูกระงับ', Shop::STATUS_SUSPENDED), 'ของร้านถูกระงับ');

        Sanctum::actingAs(User::factory()->create());

        $response = $this->getJson('/api/market/products')
            ->assertOk()
            ->assertJsonPath('has_more', false)
            ->assertJsonPath('products.0.shop.name', 'ร้านป้าแดง')
            ->assertJsonPath('products.0.price', '35.00');

        $this->assertSame(['ผักกาด'], $this->titles($response));
        $this->assertStringContainsString('/storage/product_images/', $response->json('products.0.image_url'));
    }

    public function test_market_search_and_filters(): void
    {
        $chiangMai = $this->shop('ร้านป้าแดง', province: 'เชียงใหม่');
        $bangkok = $this->shop('ครัวคุณแม่', province: 'กรุงเทพมหานคร');

        $this->product($chiangMai, 'ผักกาดหอม');
        $this->product($chiangMai, 'เสื้อผ้าฝ้าย', ['category' => 'clothing']);
        $this->product($bangkok, 'ข้าวผัดกะเพรา', ['category' => 'food']);

        Sanctum::actingAs(User::factory()->create());

        $this->assertSame(['ผักกาดหอม'], $this->titles($this->getJson('/api/market/products?q=ผักกาด')));

        // ค้นจากชื่อร้านได้
        $this->assertSame(['ข้าวผัดกะเพรา'], $this->titles($this->getJson('/api/market/products?q=ครัวคุณแม่')));

        $this->assertSame(['เสื้อผ้าฝ้าย'], $this->titles($this->getJson('/api/market/products?category=clothing')));

        $this->assertSame(
            ['ผักกาดหอม', 'เสื้อผ้าฝ้าย'],
            $this->titles($this->getJson('/api/market/products?province=' . urlencode('เชียงใหม่')))
        );

        // ตัวอักษรพิเศษของ LIKE ไม่ทำให้เจอทุกอย่าง
        $this->assertSame([], $this->titles($this->getJson('/api/market/products?q=%25')));

        $this->getJson('/api/market/products?province=Atlantis')->assertStatus(422);
    }

    // =====================================================
    // หน้าสินค้า / หน้าร้าน
    // =====================================================

    public function test_product_detail_shows_shop_contact_and_counts_views(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shop(owner: $owner);
        $product = $this->product($shop, 'ผักกาด');

        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/market/products/{$product->id}")
            ->assertOk()
            ->assertJsonPath('product.title', 'ผักกาด')
            ->assertJsonPath('product.is_mine', false)
            ->assertJsonPath('shop.phone', '0812345678')
            ->assertJsonPath('shop.line_id', '@shop')
            ->assertJsonMissingPath('shop.user_id');

        $this->assertSame(1, $product->fresh()->views);

        // เจ้าของร้านดูไม่นับยอด
        Sanctum::actingAs($owner);

        $this->getJson("/api/market/products/{$product->id}")
            ->assertOk()
            ->assertJsonPath('product.is_mine', true);

        $this->assertSame(1, $product->fresh()->views);
    }

    public function test_hidden_or_closed_items_are_not_found(): void
    {
        $owner = User::factory()->create();
        $pendingShop = $this->shop('ร้านรอตรวจ', Shop::STATUS_PENDING, owner: $owner);
        $product = $this->product($pendingShop, 'ของรอตรวจ');

        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/market/products/{$product->id}")->assertNotFound();
        $this->getJson("/api/market/shops/{$pendingShop->id}")->assertNotFound();

        // เจ้าของร้านดูตัวอย่างได้
        Sanctum::actingAs($owner);

        $this->getJson("/api/market/products/{$product->id}")->assertOk();
        $this->getJson("/api/market/shops/{$pendingShop->id}")
            ->assertOk()
            ->assertJsonPath('shop.is_mine', true);
    }

    public function test_shop_page_and_shop_strip(): void
    {
        $shop = $this->shop();
        $this->product($shop, 'ผักกาด');
        $this->product($shop, 'ซ่อนไว้', ['status' => Product::STATUS_HIDDEN]);

        // ร้านเปิดแต่ยังไม่มีสินค้า → ไม่แสดงในแถบร้าน
        $this->shop('ร้านว่าง');

        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/market/shops/{$shop->id}")
            ->assertOk()
            ->assertJsonPath('shop.name', 'ร้านป้าแดง')
            ->assertJsonCount(1, 'products');

        $this->getJson('/api/market/shops')
            ->assertOk()
            ->assertJsonCount(1, 'shops')
            ->assertJsonPath('shops.0.products_count', 1);
    }

    public function test_blocked_owner_shop_is_hidden(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shop(owner: $owner);
        $this->product($shop, 'ผักกาด');

        $viewer = User::factory()->create();
        $viewer->blockedUsers()->attach($owner->id);

        Sanctum::actingAs($viewer);

        $this->assertSame([], $this->titles($this->getJson('/api/market/products')));
        $this->getJson("/api/market/shops/{$shop->id}")->assertNotFound();
        $this->getJson('/api/market/shops')->assertJsonCount(0, 'shops');
    }

    // =====================================================
    // รายงานสินค้า → ครบ 3 คนซ่อนอัตโนมัติ / รายงานร้าน
    // =====================================================

    public function test_reported_product_is_hidden_after_three_reports(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shop(owner: $owner);
        $product = $this->product($shop, 'ของต้องห้าม');

        $reporters = User::factory()->count(3)->create();

        Sanctum::actingAs($reporters[0]);

        $this->postJson("/api/market/products/{$product->id}/report", ['reason' => 'prohibited'])
            ->assertOk();

        // คนที่รายงานแล้วไม่เห็นสินค้านี้อีก
        $this->assertSame([], $this->titles($this->getJson('/api/market/products')));

        $this->postJson("/api/market/products/{$product->id}/report", ['reason' => 'bogus'])
            ->assertStatus(422);

        Sanctum::actingAs($reporters[1]);
        $this->postJson("/api/market/products/{$product->id}/report", ['reason' => 'scam'])->assertOk();

        $this->assertNull($product->fresh()->hidden_at);

        Sanctum::actingAs($reporters[2]);
        $this->postJson("/api/market/products/{$product->id}/report", ['reason' => 'fake'])->assertOk();

        $this->assertNotNull($product->fresh()->hidden_at);

        Sanctum::actingAs($owner);

        $this->postJson("/api/market/products/{$product->id}/report", ['reason' => 'spam'])
            ->assertStatus(422);
    }

    public function test_user_can_report_shop(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shop(owner: $owner);

        Sanctum::actingAs(User::factory()->create());

        $this->postJson("/api/market/shops/{$shop->id}/report", [
            'reason' => 'scam',
            'details' => 'โอนเงินแล้วไม่ส่งของ',
        ])->assertOk();

        $this->assertSame(1, $shop->reports()->count());

        Sanctum::actingAs($owner);

        $this->postJson("/api/market/shops/{$shop->id}/report", ['reason' => 'scam'])
            ->assertStatus(422);
    }

    // =====================================================
    // Admin: ซ่อน / คืนสินค้า
    // =====================================================

    public function test_admin_can_hide_and_restore_products(): void
    {
        $admin = User::factory()->create();
        $admin->is_admin = true;
        $admin->save();

        $product = $this->product($this->shop(), 'ผักกาด');

        $this->actingAs($admin)
            ->get('/admin/products')
            ->assertOk()
            ->assertSee('ผักกาด');

        Livewire::test(ListProducts::class)
            ->callAction(TestAction::make('hide')->table($product));

        $this->assertNotNull($product->fresh()->hidden_at);

        Livewire::test(ListProducts::class)
            ->callAction(TestAction::make('restore')->table($product->fresh()));

        $this->assertNull($product->fresh()->hidden_at);
    }
}
