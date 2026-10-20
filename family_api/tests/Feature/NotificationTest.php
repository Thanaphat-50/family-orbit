<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class NotificationTest extends TestCase
{
    use RefreshDatabase;

    private function notify(User $user, array $overrides = []): AppNotification
    {
        return AppNotification::create([
            'user_id' => $user->id,
            'type' => 'new_post',
            'title' => 'โพสต์ใหม่',
            'message' => 'มีโพสต์ใหม่',
            'data' => ['post_id' => 1],
            'is_read' => false,
            ...$overrides,
        ]);
    }

    // =====================================================
    // แบ่งหน้า (ใหม่ล่าสุดก่อน)
    // =====================================================

    public function test_notifications_are_paginated_newest_first(): void
    {
        $user = User::factory()->create();

        for ($i = 1; $i <= 25; $i++) {
            $this->notify($user, ['title' => "แจ้งเตือน {$i}"]);
        }

        // ของคนอื่นต้องไม่ปนมา
        $this->notify(User::factory()->create());

        Sanctum::actingAs($user);

        $first = $this->getJson('/api/notifications')
            ->assertOk()
            ->assertJsonCount(20, 'notifications')
            ->assertJsonPath('notifications.0.title', 'แจ้งเตือน 25')
            ->assertJsonPath('has_more', true);

        $lastId = $first->json('notifications.19.id');

        $this->getJson("/api/notifications?before_id={$lastId}")
            ->assertOk()
            ->assertJsonCount(5, 'notifications')
            ->assertJsonPath('notifications.0.title', 'แจ้งเตือน 5')
            ->assertJsonPath('has_more', false);
    }

    // ลบรายการระหว่างเลื่อน → ชุดถัดไปต้องไม่ข้ามรายการใด
    public function test_deleting_while_scrolling_does_not_skip_items(): void
    {
        $user = User::factory()->create();

        for ($i = 1; $i <= 25; $i++) {
            $this->notify($user, ['title' => "แจ้งเตือน {$i}"]);
        }

        Sanctum::actingAs($user);

        $first = $this->getJson('/api/notifications');

        $this->deleteJson('/api/notifications/' . $first->json('notifications.1.id'))->assertOk();

        $titles = collect(
            $this->getJson('/api/notifications?before_id=' . $first->json('notifications.19.id'))
                ->json('notifications')
        )->pluck('title')->all();

        $this->assertSame(
            ['แจ้งเตือน 5', 'แจ้งเตือน 4', 'แจ้งเตือน 3', 'แจ้งเตือน 2', 'แจ้งเตือน 1'],
            $titles
        );
    }

    // =====================================================
    // ลบทีละรายการ / ลบที่อ่านแล้ว
    // =====================================================

    public function test_user_can_delete_own_notification_only(): void
    {
        $user = User::factory()->create();
        $other = User::factory()->create();

        $mine = $this->notify($user);
        $theirs = $this->notify($other);

        Sanctum::actingAs($user);

        $this->deleteJson("/api/notifications/{$theirs->id}")->assertForbidden();
        $this->deleteJson("/api/notifications/{$mine->id}")->assertOk();

        $this->assertModelMissing($mine);
        $this->assertModelExists($theirs);
    }

    public function test_clear_read_keeps_unread_notifications(): void
    {
        $user = User::factory()->create();

        $read = $this->notify($user, ['is_read' => true]);
        $unread = $this->notify($user);
        $othersRead = $this->notify(User::factory()->create(), ['is_read' => true]);

        Sanctum::actingAs($user);

        $this->deleteJson('/api/notifications/read')
            ->assertOk()
            ->assertJsonPath('deleted', 1);

        $this->assertModelMissing($read);
        $this->assertModelExists($unread);
        $this->assertModelExists($othersRead);
    }

    // =====================================================
    // ลบอัตโนมัติ: อ่านแล้ว + เก่ากว่า 90 วัน
    // =====================================================

    public function test_old_read_notifications_are_pruned(): void
    {
        $user = User::factory()->create();

        $oldRead = $this->notify($user, ['is_read' => true]);
        $oldUnread = $this->notify($user);
        $newRead = $this->notify($user, ['is_read' => true]);

        AppNotification::whereKey([$oldRead->id, $oldUnread->id])
            ->update(['created_at' => now()->subDays(91)]);

        $this->artisan('model:prune', ['--model' => [AppNotification::class]])
            ->assertSuccessful();

        $this->assertModelMissing($oldRead);
        $this->assertModelExists($oldUnread);
        $this->assertModelExists($newRead);
    }
}
