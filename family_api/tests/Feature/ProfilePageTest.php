<?php

namespace Tests\Feature;

use App\Models\Family;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\Shop;
use App\Models\User;
use App\Models\UserBlock;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

// หน้าโปรไฟล์ของตัวเอง: สถิติ / รายชื่อผู้ติดตาม / ตัวกรองโพสต์ของฉัน / ร้านค้า
// และ "ดูโปรไฟล์ที่คนอื่นเห็น" ต้องไม่เปิดเผยโพสต์ในกลุ่ม
class ProfilePageTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function makePost(User $author, ?Family $family, string $visibility, string $content): Post
    {
        return Post::create([
            'family_id' => $family?->id,
            'user_id' => $author->id,
            'visibility' => $visibility,
            'content' => $content,
        ]);
    }

    public function test_own_profile_stats_and_shop_status(): void
    {
        $me = User::factory()->create();
        $relative = User::factory()->create();
        $family = $this->createFamily($me, [$relative]);

        $this->makePost($me, $family, 'family', 'group 1');
        $this->makePost($me, $family, 'family', 'group 2');
        $this->makePost($me, $family, 'community', 'public');

        // ติดตามเรา 2 คน (1 คนบล็อกกันอยู่ → ไม่นับ) / เราติดตาม 1 คน
        $fan = User::factory()->create();
        $blockedFan = User::factory()->create();
        $idol = User::factory()->create();

        $fan->following()->attach($me->id);
        $blockedFan->following()->attach($me->id);
        $me->following()->attach($idol->id);

        UserBlock::create(['user_id' => $me->id, 'blocked_user_id' => $blockedFan->id]);

        Sanctum::actingAs($me);

        $this->getJson('/api/profile')
            ->assertOk()
            ->assertJsonPath('stats.posts', 3)
            ->assertJsonPath('stats.community_posts', 1)
            ->assertJsonPath('stats.group_posts', 2)
            ->assertJsonPath('stats.followers', 1)
            ->assertJsonPath('stats.following', 1)
            ->assertJsonPath('shop', null);

        $shop = Shop::create([
            'user_id' => $me->id,
            'name' => 'ร้านของฉัน',
            'category' => 'food',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => Shop::STATUS_ACTIVE,
        ]);

        $this->getJson('/api/profile')
            ->assertJsonPath('shop.id', $shop->id)
            ->assertJsonPath('shop.status', Shop::STATUS_ACTIVE);
    }

    public function test_follower_and_following_lists_are_my_own_and_skip_blocked_users(): void
    {
        $me = User::factory()->create();
        $friend = User::factory()->create(['name' => 'Friend']);
        $fan = User::factory()->create(['name' => 'Fan']);
        $blocker = User::factory()->create(['name' => 'Blocker']);

        // เพื่อนติดตามกันทั้งสองทาง / แฟนติดตามเราฝ่ายเดียว / คนที่บล็อกเราไม่แสดง
        $friend->following()->attach($me->id);
        $me->following()->attach($friend->id);
        $fan->following()->attach($me->id);
        $blocker->following()->attach($me->id);

        UserBlock::create(['user_id' => $blocker->id, 'blocked_user_id' => $me->id]);

        Sanctum::actingAs($me);

        $followers = collect($this->getJson('/api/me/followers')
            ->assertOk()
            ->assertJsonPath('has_more', false)
            ->json('users'));

        $this->assertEqualsCanonicalizing(['Friend', 'Fan'], $followers->pluck('name')->all());
        $this->assertTrue($followers->firstWhere('name', 'Friend')['is_following']);
        $this->assertFalse($followers->firstWhere('name', 'Fan')['is_following']);
        $this->assertTrue($followers->firstWhere('name', 'Fan')['follows_me']);
        $this->assertArrayNotHasKey('email', $followers->first());

        $this->getJson('/api/me/following')
            ->assertOk()
            ->assertJsonCount(1, 'users')
            ->assertJsonPath('users.0.name', 'Friend')
            ->assertJsonPath('users.0.follows_me', true);

        // ตัวเลขในหน้าโปรไฟล์ตรงกับรายชื่อ
        $this->getJson('/api/profile')->assertJsonPath('stats.followers', 2);
    }

    public function test_follower_list_is_paginated(): void
    {
        $me = User::factory()->create();

        User::factory()->count(31)->create()->each(fn (User $user) => $user->following()->attach($me->id));

        Sanctum::actingAs($me);

        $this->getJson('/api/me/followers')->assertJsonCount(30, 'users')->assertJsonPath('has_more', true);
        $this->getJson('/api/me/followers?page=2')->assertJsonCount(1, 'users')->assertJsonPath('has_more', false);
    }

    public function test_my_posts_filter_works_with_paging(): void
    {
        $me = User::factory()->create();
        $family = $this->createFamily($me);

        // ชุมชน 21 โพสต์ (2 หน้า) + กลุ่ม 2 โพสต์
        for ($i = 1; $i <= 21; $i++) {
            $this->makePost($me, $family, 'community', "public {$i}");
        }

        $this->makePost($me, $family, 'family', 'group A');
        $this->makePost($me, $family, 'family', 'group B');

        Sanctum::actingAs($me);

        $community = $this->getJson('/api/posts?scope=mine&visibility=community')
            ->assertOk()
            ->assertJsonPath('visibility', 'community')
            ->assertJsonCount(20, 'posts')
            ->assertJsonPath('has_more', true)
            ->json('posts');

        $this->assertTrue(collect($community)->every(fn ($post) => $post['visibility'] === 'community'));

        // หน้าถัดไปยังกรองอยู่ (ไม่ปนโพสต์กลุ่ม)
        $this->getJson('/api/posts?scope=mine&visibility=community&page=2')
            ->assertJsonCount(1, 'posts')
            ->assertJsonPath('posts.0.visibility', 'community')
            ->assertJsonPath('has_more', false);

        $group = collect($this->getJson('/api/posts?scope=mine&visibility=family')
            ->assertJsonCount(2, 'posts')
            ->json('posts'));

        $this->assertEqualsCanonicalizing(['group A', 'group B'], $group->pluck('content')->all());

        $this->getJson('/api/posts?scope=mine')->assertJsonCount(20, 'posts')->assertJsonPath('has_more', true);
        $this->getJson('/api/posts?scope=mine&page=2')->assertJsonCount(3, 'posts');

        $this->getJson('/api/posts?scope=mine&visibility=secret')->assertUnprocessable();
    }

    public function test_user_without_a_group_still_sees_their_community_posts(): void
    {
        $owner = User::factory()->create();
        $me = User::factory()->create();
        $family = $this->createFamily($owner, [$me]);

        $this->makePost($me, $family, 'community', 'still public');
        $this->makePost($me, $family, 'family', 'old group post');

        // ออกจากกลุ่ม
        FamilyMember::where('user_id', $me->id)->delete();

        Sanctum::actingAs($me);

        $this->getJson('/api/posts?scope=mine')
            ->assertOk()
            ->assertJsonCount(1, 'posts')
            ->assertJsonPath('posts.0.content', 'still public');

        $this->getJson('/api/posts?scope=mine&visibility=family')->assertOk()->assertJsonCount(0, 'posts');

        $this->getJson('/api/profile')
            ->assertJsonPath('stats.posts', 1)
            ->assertJsonPath('stats.group_posts', 0);
    }

    public function test_view_as_others_hides_group_posts_but_group_members_still_see_them(): void
    {
        $me = User::factory()->create();
        $relative = User::factory()->create();
        $family = $this->createFamily($me, [$relative]);

        $this->makePost($me, $family, 'community', 'public post');
        $this->makePost($me, $family, 'family', 'group only');

        // "ดูโปรไฟล์ที่คนอื่นเห็น" (เปิดโปรไฟล์สาธารณะของตัวเอง)
        Sanctum::actingAs($me);

        $this->getJson("/api/users/{$me->id}/profile")
            ->assertOk()
            ->assertJsonPath('profile.posts', 1)
            ->assertJsonMissingPath('profile.email');

        $this->getJson("/api/posts?scope=user&user_id={$me->id}")
            ->assertOk()
            ->assertJsonCount(1, 'posts')
            ->assertJsonPath('posts.0.content', 'public post');

        // คนในกลุ่มเดียวกันยังเห็นโพสต์ในกลุ่ม
        Sanctum::actingAs($relative);

        $this->getJson("/api/users/{$me->id}/profile")->assertJsonPath('profile.posts', 2);
        $this->getJson("/api/posts?scope=user&user_id={$me->id}")->assertJsonCount(2, 'posts');

        // คนนอกกลุ่มเห็นเฉพาะโพสต์ชุมชน และไม่เห็นชื่อกลุ่ม
        Sanctum::actingAs(User::factory()->create());

        $response = $this->getJson("/api/users/{$me->id}/profile")
            ->assertJsonPath('profile.posts', 1)
            ->assertJsonPath('profile.family_role', null);

        $this->assertStringNotContainsString($family->name, $response->getContent());
        $this->assertStringNotContainsString((string) $me->email, $response->getContent());

        $this->getJson("/api/posts?scope=user&user_id={$me->id}")->assertJsonCount(1, 'posts');
    }
}
