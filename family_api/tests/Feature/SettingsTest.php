<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Shop;
use App\Models\User;
use App\Models\UserLocation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class SettingsTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    // =====================================================
    // ค่าเริ่มต้น: แชร์ตำแหน่ง + รับแจ้งเตือนทุกประเภท
    // =====================================================

    public function test_default_settings(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/settings')
            ->assertOk()
            ->assertJsonPath('settings.location_sharing', true)
            ->assertJsonPath('settings.notifications.new_post', true)
            ->assertJsonPath('settings.notifications.member_joined', true);
    }

    public function test_update_settings_partially(): void
    {
        $user = User::factory()->create();

        Sanctum::actingAs($user);

        $this->putJson('/api/settings', ['notifications' => ['new_post' => false]])
            ->assertOk()
            ->assertJsonPath('settings.notifications.new_post', false)
            ->assertJsonPath('settings.notifications.new_comment', true);

        // เปลี่ยนอีกค่า → ค่าเดิมต้องยังอยู่
        $this->putJson('/api/settings', ['notifications' => ['new_comment' => false]])
            ->assertJsonPath('settings.notifications.new_post', false)
            ->assertJsonPath('settings.notifications.new_comment', false);

        // ผลตรวจร้านค้าปิดไม่ได้ / ค่าไม่ใช่ true-false
        $this->putJson('/api/settings', ['notifications' => ['shop_status' => false]])
            ->assertStatus(422);

        $this->putJson('/api/settings', ['location_sharing' => 'maybe'])
            ->assertStatus(422);

        // ไม่ส่งค่าตั้งค่าให้ผู้ใช้อื่นเห็นผ่านข้อมูลผู้ใช้
        $this->assertArrayNotHasKey('notification_settings', $user->fresh()->toArray());
    }

    // =====================================================
    // ปิดการแจ้งเตือนประเภทไหน → ไม่ได้รับประเภทนั้น
    // =====================================================

    public function test_disabled_notification_types_are_not_created(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();
        $kid = User::factory()->create();

        $this->createFamily($mom, [$dad, $kid]);

        $dad->notification_settings = ['new_post' => false];
        $dad->save();

        Sanctum::actingAs($mom);

        $this->postJson('/api/posts', ['content' => 'Dinner at 7'])->assertCreated();

        $this->assertSame(0, AppNotification::where('user_id', $dad->id)->count());
        $this->assertSame(1, AppNotification::where('user_id', $kid->id)->count());

        // ประเภทที่ปิดไม่ได้ยังส่งเสมอ
        $dad->notification_settings = ['new_post' => false, 'shop_status' => false];
        $dad->save();

        $shop = Shop::create([
            'user_id' => $dad->id,
            'name' => 'ร้านพ่อ',
            'category' => 'food',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => Shop::STATUS_PENDING,
        ]);

        $shop->approve();

        $this->assertSame(1, AppNotification::where('user_id', $dad->id)->where('type', 'shop_status')->count());
    }

    // =====================================================
    // ปิดการแชร์ตำแหน่ง
    // =====================================================

    public function test_turning_off_location_sharing_hides_location(): void
    {
        $mom = User::factory()->create(['name' => 'แม่']);
        $dad = User::factory()->create(['name' => 'พ่อ']);

        $this->createFamily($mom, [$dad]);

        Sanctum::actingAs($dad);

        $this->postJson('/api/location', ['latitude' => 13.7, 'longitude' => 100.5])->assertOk();

        $this->putJson('/api/settings', ['location_sharing' => false])
            ->assertOk()
            ->assertJsonPath('settings.location_sharing', false);

        // ตำแหน่งเดิมถูกลบ และตำแหน่งใหม่ไม่ถูกเก็บ
        $this->assertSame(0, UserLocation::where('user_id', $dad->id)->count());

        $this->postJson('/api/location', ['latitude' => 13.8, 'longitude' => 100.6])
            ->assertOk()
            ->assertJsonPath('shared', false);

        $this->assertSame(0, UserLocation::where('user_id', $dad->id)->count());

        // แม่เห็นว่าพ่อปิดการแชร์อยู่
        Sanctum::actingAs($mom);

        $this->postJson('/api/location', ['latitude' => 13.7, 'longitude' => 100.5])->assertOk();

        $this->getJson('/api/family/locations')
            ->assertOk()
            ->assertJsonCount(1, 'locations')
            ->assertJsonPath('locations.0.user.name', 'แม่')
            ->assertJsonPath('paused.0.name', 'พ่อ');

        // พ่อดูเอง → ไม่มีชื่อตัวเองในรายชื่อที่ปิดแชร์
        Sanctum::actingAs($dad);

        $this->getJson('/api/family/locations')
            ->assertOk()
            ->assertJsonCount(0, 'paused');

        // เปิดอีกครั้ง → ส่งตำแหน่งได้ตามปกติ

        $this->putJson('/api/settings', ['location_sharing' => true])->assertOk();

        $this->postJson('/api/location', ['latitude' => 13.8, 'longitude' => 100.6])->assertOk();

        $this->assertSame(1, UserLocation::where('user_id', $dad->id)->count());
    }
}
