<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\ProductImage;
use App\Models\Shop;
use App\Models\User;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

class MyProductTest extends TestCase
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
            'terms_accepted_at' => now(),
        ]);
    }

    private function productForm(array $overrides = []): array
    {
        return [
            'title' => 'ผักกาดหอม',
            'description' => 'ปลูกเอง ไม่ใช้สารเคมี',
            'price' => '35',
            'category' => 'produce',
            'images' => [$this->fakePng('a.png'), $this->fakePng('b.png')],
            ...$overrides,
        ];
    }

    private function storedImages(): array
    {
        return Storage::disk(MediaStorage::disk())->allFiles('product_images');
    }

    // =====================================================
    // เพิ่มสินค้าพร้อมรูป → เห็นในรายการสินค้าของร้าน
    // =====================================================

    public function test_owner_can_add_product_with_images(): void
    {
        $owner = User::factory()->create();
        $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop/products', $this->productForm())
            ->assertCreated()
            ->assertJsonPath('product.title', 'ผักกาดหอม')
            ->assertJsonPath('product.price', '35.00')
            ->assertJsonCount(2, 'product.images')
            ->assertJsonMissingPath('product.images.0.path');

        $this->assertCount(2, $this->storedImages());

        $this->getJson('/api/my-shop/products')
            ->assertOk()
            ->assertJsonCount(1, 'products')
            ->assertJsonPath('limit', 30)
            ->assertJsonPath('max_images', 5);

        // ไม่ใส่ราคา = สอบถามราคา
        $this->postJson('/api/my-shop/products', $this->productForm(['price' => null]))
            ->assertCreated()
            ->assertJsonPath('product.price', null);
    }

    public function test_product_validation(): void
    {
        $owner = User::factory()->create();
        $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop/products', $this->productForm(['images' => []]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('images');

        $sixImages = array_map(fn ($i) => $this->fakePng("p{$i}.png"), range(1, 6));

        $this->postJson('/api/my-shop/products', $this->productForm(['images' => $sixImages]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('images');

        $this->postJson('/api/my-shop/products', $this->productForm([
            'price' => '-5',
            'category' => 'weapons',
            'title' => '',
        ]))
            ->assertStatus(422)
            ->assertJsonValidationErrors(['price', 'category', 'title']);

        $this->postJson('/api/my-shop/products', $this->productForm([
            'images' => [UploadedFile::fake()->create('doc.pdf', 10, 'application/pdf')],
        ]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('images.0');

        $this->assertSame(0, Product::count());
        $this->assertSame([], $this->storedImages());
    }

    public function test_product_limit_per_shop(): void
    {
        config(['market.max_products_per_shop' => 2]);

        $owner = User::factory()->create();
        $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop/products', $this->productForm())->assertCreated();
        $this->postJson('/api/my-shop/products', $this->productForm())->assertCreated();

        $this->postJson('/api/my-shop/products', $this->productForm())
            ->assertStatus(422)
            ->assertJsonPath('message', 'ลงสินค้าได้สูงสุด 2 ชิ้น ลบสินค้าเก่าก่อนเพิ่มใหม่');

        $this->assertSame(2, Product::count());
        $this->assertCount(4, $this->storedImages());
    }

    // =====================================================
    // แก้ไข: เอารูปเดิมออก / เพิ่มรูปใหม่ (ต้องเหลือ 1–5 รูป)
    // =====================================================

    public function test_owner_can_update_product_and_images(): void
    {
        $owner = User::factory()->create();
        $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $product = $this->postJson('/api/my-shop/products', $this->productForm())->json('product');

        [$first, $second] = $product['images'];

        $removedPath = ProductImage::find($first['id'])->path;

        $this->postJson('/api/my-shop/products/' . $product['id'] . '/update', [
            ...$this->productForm(['title' => 'ผักกาดหอม (ถุงใหญ่)', 'price' => '50']),
            'images' => [$this->fakePng('c.png')],
            'remove_image_ids' => [$first['id']],
        ])
            ->assertOk()
            ->assertJsonPath('product.title', 'ผักกาดหอม (ถุงใหญ่)')
            ->assertJsonPath('product.price', '50.00')
            ->assertJsonCount(2, 'product.images')
            ->assertJsonPath('product.images.0.id', $second['id'])
            ->assertJsonPath('product.images.0.sort', 0);

        $this->assertFalse(Storage::disk(MediaStorage::disk())->exists($removedPath));
        $this->assertCount(2, $this->storedImages());

        // เอารูปออกจนหมด → ไม่ได้
        $ids = Product::find($product['id'])->images->pluck('id')->all();

        $this->postJson('/api/my-shop/products/' . $product['id'] . '/update', [
            ...$this->productForm(),
            'images' => [],
            'remove_image_ids' => $ids,
        ])
            ->assertStatus(422)
            ->assertJsonPath('message', 'สินค้าต้องมีรูปอย่างน้อย 1 รูป');

        $this->assertCount(2, $this->storedImages());
    }

    public function test_owner_can_hide_and_delete_product(): void
    {
        $owner = User::factory()->create();
        $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $id = $this->postJson('/api/my-shop/products', $this->productForm())->json('product.id');

        $this->patchJson("/api/my-shop/products/{$id}/status", ['status' => 'hidden'])
            ->assertOk()
            ->assertJsonPath('product.status', 'hidden');

        $this->patchJson("/api/my-shop/products/{$id}/status", ['status' => 'sold'])
            ->assertStatus(422);

        $this->deleteJson("/api/my-shop/products/{$id}")->assertOk();

        $this->assertSame(0, Product::count());
        $this->assertSame([], $this->storedImages());
    }

    // =====================================================
    // สิทธิ์: สินค้าร้านอื่น / ไม่มีร้าน / ร้านถูกระงับ
    // =====================================================

    public function test_cannot_touch_other_shops_products(): void
    {
        $owner = User::factory()->create();
        $other = User::factory()->create();
        $this->shopOf($owner);
        $this->shopOf($other);

        Sanctum::actingAs($owner);

        $id = $this->postJson('/api/my-shop/products', $this->productForm())->json('product.id');

        Sanctum::actingAs($other);

        $this->postJson("/api/my-shop/products/{$id}/update", $this->productForm())->assertNotFound();
        $this->patchJson("/api/my-shop/products/{$id}/status", ['status' => 'hidden'])->assertNotFound();
        $this->deleteJson("/api/my-shop/products/{$id}")->assertNotFound();

        $this->assertSame(1, Product::count());
    }

    public function test_requires_shop_and_blocks_suspended_shop(): void
    {
        $noShop = User::factory()->create();

        Sanctum::actingAs($noShop);

        $this->getJson('/api/my-shop/products')->assertNotFound();
        $this->postJson('/api/my-shop/products', $this->productForm())->assertNotFound();

        $owner = User::factory()->create();
        $this->shopOf($owner, Shop::STATUS_SUSPENDED);

        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop/products', $this->productForm())->assertForbidden();

        $this->assertSame([], $this->storedImages());
    }

    // =====================================================
    // ลบบัญชี → รูปสินค้าและโลโก้ถูกลบด้วย
    // =====================================================

    public function test_account_deletion_removes_product_images(): void
    {
        $owner = User::factory()->create(['password' => 'secret-pass']);
        $this->shopOf($owner);

        Sanctum::actingAs($owner);

        $this->postJson('/api/my-shop/products', $this->productForm())->assertCreated();

        // ผู้ดูแลอนุมัติคำขอลบบัญชี
        app(\App\Services\AccountDeletionService::class)->delete($owner->fresh());

        $this->assertSame(0, Product::count());
        $this->assertSame(0, ProductImage::count());
        $this->assertSame([], $this->storedImages());
    }
}
