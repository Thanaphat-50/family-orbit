<?php

namespace Tests\Feature;

use App\Models\Post;
use App\Models\User;
use App\Models\UserLocation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class MapStatusTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function locate(User $user, float $latitude = 13.75, float $longitude = 100.5): void
    {
        UserLocation::create([
            'user_id' => $user->id,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'last_seen_at' => now(),
        ]);
    }

    private function statusSeenBy(User $viewer, User $member): ?array
    {
        Sanctum::actingAs($viewer);

        $locations = $this->getJson('/api/family/locations')
            ->assertOk()
            ->json('locations');

        foreach ($locations as $location) {
            if ($location['user_id'] === $member->id) {
                return $location['status'];
            }
        }

        $this->fail('Member location not found');
    }

    // =====================================================
    // โพสต์ครอบครัวพร้อม "แสดงบนแผนที่" → ครอบครัวเห็นข้างตำแหน่ง
    // =====================================================

    public function test_family_post_can_show_on_the_map(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $this->createFamily($mom, [$dad]);
        $this->locate($dad);

        Sanctum::actingAs($dad);

        $postId = $this->postJson('/api/posts', [
            'content' => 'ทำงานอยู่',
            'show_on_map' => true,
        ])
            ->assertCreated()
            ->assertJsonPath('post.on_map', true)
            ->json('post.id');

        $status = $this->statusSeenBy($mom, $dad);

        $this->assertSame('ทำงานอยู่', $status['text']);
        $this->assertSame($postId, $status['post_id']);

        // ฟีดครอบครัวบอกว่าโพสต์นี้อยู่บนแผนที่
        $this->getJson('/api/posts?scope=family')
            ->assertOk()
            ->assertJsonPath('posts.0.on_map', true);
    }

    public function test_normal_and_community_posts_do_not_show_on_the_map(): void
    {
        $mom = User::factory()->create(['community_terms_accepted_at' => now()]);
        $dad = User::factory()->create();

        $this->createFamily($mom, [$dad]);
        $this->locate($mom);

        Sanctum::actingAs($mom);

        $this->postJson('/api/posts', ['content' => 'โพสต์ปกติ'])
            ->assertCreated()
            ->assertJsonPath('post.on_map', false);

        $this->postJson('/api/posts', [
            'content' => 'ชุมชน',
            'visibility' => 'community',
            'show_on_map' => true,
        ])
            ->assertCreated()
            ->assertJsonPath('post.on_map', false);

        $this->assertNull($this->statusSeenBy($dad, $mom));
    }

    public function test_new_status_replaces_the_old_one_and_expires(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $this->createFamily($mom, [$dad]);
        $this->locate($dad);

        Sanctum::actingAs($dad);

        $first = $this->postJson('/api/posts', ['content' => 'ทำงานอยู่', 'show_on_map' => true])
            ->json('post.id');

        $this->postJson('/api/posts', ['content' => 'กำลังกลับบ้าน', 'show_on_map' => true])
            ->assertCreated();

        $this->assertSame('กำลังกลับบ้าน', $this->statusSeenBy($mom, $dad)['text']);
        $this->assertFalse(Post::find($first)->on_map);

        $this->travel(Post::MAP_STATUS_HOURS + 1)->hours();

        $this->assertNull($this->statusSeenBy($mom, $dad));
    }

    // =====================================================
    // แสดง / เอาออกภายหลัง
    // =====================================================

    public function test_owner_can_add_and_remove_an_existing_post(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $family = $this->createFamily($mom, [$dad]);
        $this->locate($dad);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $dad->id,
            'visibility' => 'family',
            'content' => 'ไปรับลูก',
        ]);

        // คนอื่นตั้งให้ไม่ได้
        Sanctum::actingAs($mom);

        $this->postJson("/api/posts/{$post->id}/map-status")->assertForbidden();

        Sanctum::actingAs($dad);

        $this->postJson("/api/posts/{$post->id}/map-status")
            ->assertOk()
            ->assertJsonPath('on_map', true);

        $this->assertSame('ไปรับลูก', $this->statusSeenBy($mom, $dad)['text']);

        Sanctum::actingAs($dad);

        $this->deleteJson("/api/posts/{$post->id}/map-status")
            ->assertOk()
            ->assertJsonPath('on_map', false);

        $this->assertNull($this->statusSeenBy($mom, $dad));
    }

    public function test_photo_only_post_cannot_show_on_the_map(): void
    {
        $mom = User::factory()->create();

        $family = $this->createFamily($mom);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'visibility' => 'family',
            'content' => '',
        ]);

        Sanctum::actingAs($mom);

        $this->postJson("/api/posts/{$post->id}/map-status")->assertStatus(422);
    }

    // อีกครอบครัวไม่เห็นข้อความ แม้โพสต์จะอยู่บนแผนที่
    public function test_status_stays_inside_the_family(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();
        $stranger = User::factory()->create();

        $this->createFamily($mom, [$dad]);
        $this->createFamily($stranger);
        $this->locate($dad);
        $this->locate($stranger);

        Sanctum::actingAs($dad);

        $this->postJson('/api/posts', ['content' => 'ทำงานอยู่', 'show_on_map' => true])
            ->assertCreated();

        Sanctum::actingAs($stranger);

        $this->getJson('/api/family/locations')
            ->assertOk()
            ->assertJsonCount(1, 'locations')
            ->assertJsonPath('locations.0.user_id', $stranger->id)
            ->assertJsonPath('locations.0.status', null);
    }
}
