<?php

namespace Tests\Feature;

use App\Filament\Resources\Shops\Pages\ListShops;
use App\Models\AppNotification;
use App\Models\Shop;
use App\Models\User;
use App\Support\MediaStorage;
use Filament\Actions\Testing\TestAction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

class ShopTest extends TestCase
{
    use FakesImages, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());
    }

    private function shopForm(array $overrides = []): array
    {
        return [
            'name' => 'ร้านป้าแดง',
            'description' => 'ผักปลอดสารจากสวน',
            'category' => 'produce',
            'phone' => '081-234-5678',
            'line_id' => '@padaeng',
            'province' => 'เชียงใหม่',
            'district' => 'สันทราย',
            'accept_terms' => '1',
            ...$overrides,
        ];
    }

    private function createShop(User $owner, string $status = Shop::STATUS_PENDING): Shop
    {
        return Shop::create([
            'user_id' => $owner->id,
            'name' => 'ร้านลุง',
            'category' => 'food',
            'phone' => '0812345678',
            'province' => 'กรุงเทพมหานคร',
            'status' => $status,
            'terms_accepted_at' => now(),
        ]);
    }

    private function logoFiles(): array
    {
        return Storage::disk(MediaStorage::disk())->allFiles('shop_logos');
    }

    public function test_province_list_has_all_77_provinces(): void
    {
        $provinces = config('market.provinces');

        $this->assertCount(77, $provinces);
        $this->assertCount(77, array_unique($provinces));
    }

    // =====================================================
    // สมัครเปิดร้าน → รออนุมัติ
    // =====================================================

    public function test_user_can_apply_for_a_shop(): void
    {
        $user = User::factory()->create();

        Sanctum::actingAs($user);

        $this->getJson('/api/my-shop')
            ->assertOk()
            ->assertJsonPath('shop', null);

        $this->postJson('/api/my-shop', $this->shopForm([
            'logo' => $this->fakePng('logo.png'),
        ]))
            ->assertCreated()
            ->assertJsonPath('shop.status', Shop::STATUS_PENDING)
            ->assertJsonPath('shop.phone', '0812345678')
            ->assertJsonMissingPath('shop.logo_path');

        $this->assertCount(1, $this->logoFiles());

        $this->getJson('/api/my-shop')
            ->assertOk()
            ->assertJsonPath('shop.name', 'ร้านป้าแดง')
            ->assertJsonPath('shop.status_label', 'รออนุมัติ');

        $this->assertNotNull(Shop::first()->terms_accepted_at);
    }

    public function test_apply_validates_fields_and_terms(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/my-shop', $this->shopForm(['accept_terms' => null]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('accept_terms');

        $this->postJson('/api/my-shop', $this->shopForm([
            'province' => 'Atlantis',
            'phone' => 'call me',
            'category' => 'weapons',
        ]))
            ->assertStatus(422)
            ->assertJsonValidationErrors(['province', 'phone', 'category']);

        $this->assertSame(0, Shop::count());
    }

    public function test_user_can_have_only_one_shop(): void
    {
        $user = User::factory()->create();
        $this->createShop($user);

        Sanctum::actingAs($user);

        $this->postJson('/api/my-shop', $this->shopForm())
            ->assertStatus(409);

        $this->assertSame(1, Shop::count());
    }

    // =====================================================
    // ร้านที่ไม่ผ่าน แก้ไขแล้วส่งตรวจใหม่ / เปลี่ยนโลโก้แล้วลบไฟล์เก่า
    // =====================================================

    public function test_rejected_shop_is_resubmitted_after_update(): void
    {
        $user = User::factory()->create();

        Sanctum::actingAs($user);

        $this->postJson('/api/my-shop', $this->shopForm([
            'logo' => $this->fakePng('old.png'),
        ]))->assertCreated();

        $shop = Shop::first();
        $shop->reject('กรุณาใส่ชื่อร้านให้ชัดเจน');

        $this->getJson('/api/my-shop')
            ->assertJsonPath('shop.status', Shop::STATUS_REJECTED)
            ->assertJsonPath('shop.status_reason', 'กรุณาใส่ชื่อร้านให้ชัดเจน');

        $oldLogo = $shop->fresh()->logo_path;

        $this->postJson('/api/my-shop/update', $this->shopForm([
            'name' => 'ร้านผักป้าแดง สันทราย',
            'logo' => $this->fakePng('new.png'),
        ]))
            ->assertOk()
            ->assertJsonPath('shop.status', Shop::STATUS_PENDING)
            ->assertJsonPath('shop.status_reason', null)
            ->assertJsonPath('shop.name', 'ร้านผักป้าแดง สันทราย');

        $this->assertCount(1, $this->logoFiles());
        $this->assertFalse(Storage::disk(MediaStorage::disk())->exists($oldLogo));
    }

    public function test_update_without_shop_returns_404(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/my-shop/update', $this->shopForm())
            ->assertNotFound();
    }

    // =====================================================
    // Admin อนุมัติ / ไม่ผ่าน / ระงับ + แจ้งเตือนเจ้าของร้าน
    // =====================================================

    public function test_admin_can_approve_reject_and_suspend_shops(): void
    {
        $admin = User::factory()->create();
        $admin->is_admin = true;
        $admin->save();

        $owner = User::factory()->create();
        $other = User::factory()->create();

        $shop = $this->createShop($owner);
        $otherShop = $this->createShop($other);

        $this->actingAs($admin)
            ->get('/admin/shops')
            ->assertOk()
            ->assertSee('ร้านลุง');

        Livewire::test(ListShops::class)
            ->callAction(TestAction::make('approve')->table($shop))
            ->callAction(
                TestAction::make('reject')->table($otherShop),
                ['reason' => 'ข้อมูลติดต่อไม่ครบ']
            );

        $shop->refresh();
        $otherShop->refresh();

        $this->assertSame(Shop::STATUS_ACTIVE, $shop->status);
        $this->assertNotNull($shop->approved_at);
        $this->assertSame(Shop::STATUS_REJECTED, $otherShop->status);
        $this->assertSame('ข้อมูลติดต่อไม่ครบ', $otherShop->status_reason);

        Livewire::test(ListShops::class)
            ->callAction(
                TestAction::make('suspend')->table($shop),
                ['reason' => 'ขายสินค้าต้องห้าม']
            );

        $this->assertSame(Shop::STATUS_SUSPENDED, $shop->fresh()->status);

        $this->assertSame(
            2,
            AppNotification::where('user_id', $owner->id)->where('type', 'shop_status')->count()
        );
        $this->assertSame(
            1,
            AppNotification::where('user_id', $other->id)->where('type', 'shop_status')->count()
        );
    }

    // =====================================================
    // ลบบัญชี → ร้านและโลโก้ถูกลบด้วย
    // =====================================================

    public function test_account_deletion_removes_shop_and_logo(): void
    {
        $user = User::factory()->create(['password' => 'secret-pass']);

        Sanctum::actingAs($user);

        $this->postJson('/api/my-shop', $this->shopForm([
            'logo' => $this->fakePng(),
        ]))->assertCreated();

        $this->deleteJson('/api/account', ['password' => 'secret-pass'])
            ->assertOk();

        $this->assertSame(0, Shop::count());
        $this->assertSame([], $this->logoFiles());
    }
}
