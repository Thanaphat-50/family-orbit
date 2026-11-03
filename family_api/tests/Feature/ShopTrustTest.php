<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Product;
use App\Models\Shop;
use App\Models\ShopReview;
use App\Models\SocialAccount;
use App\Models\User;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

// ข้อมูลร้านละเอียดขึ้น / รูปหน้าร้าน / วิดีโอแนะนำ / ข้อมูลความน่าเชื่อถือ / รีวิว
class ShopTrustTest extends TestCase
{
    use FakesImages, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());
    }

    private function shopOf(User $owner, string $status = Shop::STATUS_ACTIVE): Shop
    {
        return Shop::create([
            'user_id' => $owner->id,
            'name' => 'ร้านป้าแดง',
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => $status,
            'approved_at' => $status === Shop::STATUS_ACTIVE ? now()->subMonths(3) : null,
            'terms_accepted_at' => now(),
        ]);
    }

    private function productOf(Shop $shop, array $overrides = []): Product
    {
        return Product::create([
            'shop_id' => $shop->id,
            'title' => 'ผักกาดหอม',
            'price' => 35,
            'category' => 'produce',
            'status' => Product::STATUS_ACTIVE,
            ...$overrides,
        ]);
    }

    private function video(string $name = 'clip.mp4', int $kb = 800): UploadedFile
    {
        return UploadedFile::fake()->create($name, $kb, 'video/mp4');
    }

    private function files(string $folder): array
    {
        return Storage::disk(MediaStorage::disk())->allFiles($folder);
    }

    // =====================================================
    // เวลาเปิด-ปิด + วิธีรับสินค้า
    // =====================================================

    public function test_owner_can_save_opening_hours_and_delivery_methods(): void
    {
        $owner = User::factory()->create();
        $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $form = [
            'name' => 'ร้านป้าแดง',
            'category' => 'produce',
            'phone' => '081-234-5678',
            'province' => 'เชียงใหม่',
            'opening_hours' => ' ทุกวัน 08:00–18:00 ',
            'delivery_methods' => ['meetup', 'shipping'],
        ];

        $this->postJson('/api/my-shop/update', $form)
            ->assertOk()
            ->assertJsonPath('shop.opening_hours', 'ทุกวัน 08:00–18:00')
            ->assertJsonPath('shop.delivery_methods', ['meetup', 'shipping']);

        $this->postJson('/api/my-shop/update', [...$form, 'delivery_methods' => ['teleport']])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('delivery_methods.0');
    }

    // =====================================================
    // รูปหน้าร้าน + วิดีโอแนะนำร้าน
    // =====================================================

    public function test_owner_can_add_and_remove_shop_photos_and_video(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $response = $this->post('/api/my-shop/media', [
            'images' => [$this->fakePng('a.png'), $this->fakePng('b.png')],
            'video' => $this->video(),
            'video_thumbnail' => $this->fakePng('thumb.png'),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonCount(2, 'shop.images')
            ->assertJsonMissingPath('shop.video_path');

        $this->assertNotNull($response->json('shop.video_url'));
        $this->assertCount(2, $this->files('shop_images'));
        $this->assertCount(2, $this->files('shop_videos'));

        // ลบรูปแรก + ลบวิดีโอ → ไฟล์หายจากที่เก็บด้วย
        $firstId = $response->json('shop.images.0.id');

        $this->post('/api/my-shop/media', [
            'remove_image_ids' => [$firstId],
            'remove_video' => '1',
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonCount(1, 'shop.images')
            ->assertJsonPath('shop.video_url', null);

        $this->assertCount(1, $this->files('shop_images'));
        $this->assertCount(0, $this->files('shop_videos'));
        $this->assertNull($shop->refresh()->video_path);
    }

    public function test_shop_photos_are_limited(): void
    {
        config(['market.max_shop_images' => 2]);

        $owner = User::factory()->create();
        $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $this->post('/api/my-shop/media', [
            'images' => [$this->fakePng('a.png'), $this->fakePng('b.png')],
        ], ['Accept' => 'application/json'])->assertOk();

        $this->post('/api/my-shop/media', [
            'images' => [$this->fakePng('c.png')],
        ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'รูปหน้าร้านได้ไม่เกิน 2 รูป');

        $this->assertCount(2, $this->files('shop_images'));
    }

    // =====================================================
    // วิดีโอแนะนำสินค้า
    // =====================================================

    public function test_owner_can_add_and_remove_product_video(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shopOf($owner);
        $product = $this->productOf($shop);

        Sanctum::actingAs($owner);

        $this->post("/api/my-shop/products/{$product->id}/video", [
            'video' => $this->video(),
            'video_thumbnail' => $this->fakePng('t.png'),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonMissingPath('product.video_path');

        $this->assertCount(2, $this->files('product_videos'));

        // ผู้ซื้อเห็นวิดีโอในหน้าสินค้า และการ์ดบอกว่ามีวิดีโอ
        $buyer = User::factory()->create();
        Sanctum::actingAs($buyer);

        $this->assertNotNull($this->getJson("/api/market/products/{$product->id}")->assertOk()->json('product.video_url'));

        $this->getJson('/api/market/products')
            ->assertOk()
            ->assertJsonPath('products.0.has_video', true);

        // คนอื่นแก้วิดีโอสินค้าร้านนี้ไม่ได้
        $this->post("/api/my-shop/products/{$product->id}/video", [
            'video' => $this->video(),
        ], ['Accept' => 'application/json'])->assertNotFound();

        Sanctum::actingAs($owner);

        $this->deleteJson("/api/my-shop/products/{$product->id}/video")->assertOk();

        $this->assertCount(0, $this->files('product_videos'));
    }

    public function test_deleting_a_shop_removes_its_photos_and_videos(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shopOf($owner);
        $product = $this->productOf($shop);

        Sanctum::actingAs($owner);

        $this->post('/api/my-shop/media', [
            'images' => [$this->fakePng('a.png')],
            'video' => $this->video(),
        ], ['Accept' => 'application/json'])->assertOk();

        $this->post("/api/my-shop/products/{$product->id}/video", [
            'video' => $this->video(),
        ], ['Accept' => 'application/json'])->assertOk();

        $shop->refresh()->delete();

        $this->assertCount(0, $this->files('shop_images'));
        $this->assertCount(0, $this->files('shop_videos'));
        $this->assertCount(0, $this->files('product_videos'));
    }

    // =====================================================
    // ข้อมูลความน่าเชื่อถือในหน้าร้าน
    // =====================================================

    public function test_shop_page_shows_trust_info(): void
    {
        $owner = User::factory()->create(['created_at' => now()->subYear()]);
        $shop = $this->shopOf($owner);
        $this->productOf($shop);
        $this->productOf($shop, ['title' => 'ซ่อนไว้', 'status' => Product::STATUS_HIDDEN]);

        SocialAccount::create([
            'user_id' => $owner->id,
            'provider' => 'line',
            'provider_user_id' => 'U123',
        ]);

        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/market/shops/{$shop->id}")
            ->assertOk()
            ->assertJsonPath('shop.trust.reviewed_by_admin', true)
            ->assertJsonPath('shop.trust.products_count', 1)
            ->assertJsonPath('shop.trust.login_methods', ['line'])
            ->assertJsonPath('shop.rating.count', 0)
            ->assertJsonPath('shop.rating.average', null)
            ->assertJsonMissingPath('shop.trust.email')
            ->assertJsonMissingPath('shop.user_id');
    }

    // =====================================================
    // รีวิวร้าน
    // =====================================================

    public function test_buyers_can_review_a_shop_once_and_edit_it(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shopOf($owner);

        $buyer = User::factory()->create(['name' => 'ลุงสมชาย']);
        $other = User::factory()->create();

        Sanctum::actingAs($buyer);

        $this->postJson("/api/market/shops/{$shop->id}/reviews", ['rating' => 5, 'comment' => 'ผักสดมาก'])
            ->assertCreated()
            ->assertJsonPath('summary.count', 1)
            ->assertJsonPath('summary.average', 5);

        // ส่งซ้ำ = แก้ไขรีวิวเดิม (ไม่เพิ่มรีวิวใหม่ และไม่แจ้งเจ้าของซ้ำ)
        $this->postJson("/api/market/shops/{$shop->id}/reviews", ['rating' => 4])
            ->assertOk()
            ->assertJsonPath('review.rating', 4)
            ->assertJsonPath('review.comment', null);

        Sanctum::actingAs($other);

        $this->postJson("/api/market/shops/{$shop->id}/reviews", ['rating' => 3])->assertCreated();

        $this->getJson("/api/market/shops/{$shop->id}/reviews")
            ->assertOk()
            ->assertJsonCount(2, 'reviews')
            ->assertJsonPath('summary.average', 3.5)
            ->assertJsonPath('my_review.rating', 3)
            ->assertJsonPath('can_review', true);

        $this->assertSame(2, ShopReview::count());
        $this->assertSame(2, AppNotification::where('user_id', $owner->id)->where('type', 'shop_review')->count());

        $this->getJson("/api/market/shops/{$shop->id}")
            ->assertOk()
            ->assertJsonPath('shop.rating.count', 2)
            ->assertJsonCount(2, 'reviews')
            ->assertJsonPath('my_review.rating', 3);
    }

    public function test_owner_cannot_review_own_shop_and_invalid_ratings_fail(): void
    {
        $owner = User::factory()->create();
        $shop = $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $this->postJson("/api/market/shops/{$shop->id}/reviews", ['rating' => 5])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'รีวิวร้านของตัวเองไม่ได้');

        Sanctum::actingAs(User::factory()->create());

        $this->postJson("/api/market/shops/{$shop->id}/reviews", ['rating' => 6])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('rating');

        // ร้านที่ยังไม่อนุมัติ รีวิวไม่ได้
        $pending = $this->shopOf(User::factory()->create(), Shop::STATUS_PENDING);

        $this->postJson("/api/market/shops/{$pending->id}/reviews", ['rating' => 5])->assertNotFound();
    }

    public function test_hidden_reviews_are_excluded_and_reviews_can_be_deleted(): void
    {
        $shop = $this->shopOf(User::factory()->create());

        $spammer = User::factory()->create();
        $buyer = User::factory()->create();

        ShopReview::create(['shop_id' => $shop->id, 'user_id' => $spammer->id, 'rating' => 1, 'hidden_at' => now()]);
        ShopReview::create(['shop_id' => $shop->id, 'user_id' => $buyer->id, 'rating' => 5]);

        Sanctum::actingAs($buyer);

        $this->getJson("/api/market/shops/{$shop->id}/reviews")
            ->assertOk()
            ->assertJsonCount(1, 'reviews')
            ->assertJsonPath('summary.average', 5);

        $this->deleteJson("/api/market/shops/{$shop->id}/reviews")
            ->assertOk()
            ->assertJsonPath('summary.count', 0);
    }
}
