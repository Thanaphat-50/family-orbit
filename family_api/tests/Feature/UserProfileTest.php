<?php

namespace Tests\Feature;

use App\Filament\Resources\Users\Pages\ListUsers;
use App\Filament\Resources\Users\Pages\ViewUser;
use App\Models\Comment;
use App\Models\Family;
use App\Models\Post;
use App\Models\PostLike;
use App\Models\User;
use App\Models\UserReport;
use Filament\Actions\Testing\TestAction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class UserProfileTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function makePost(User $author, Family $family, string $visibility, string $content): Post
    {
        return Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => $visibility,
            'content' => $content,
        ]);
    }

    // =====================================================
    // โปรไฟล์ในชุมชน
    // =====================================================

    public function test_profile_of_community_poster_shows_public_info_and_stats(): void
    {
        $author = User::factory()->create(['name' => 'Aunt Daeng']);
        $authorFamily = $this->createFamily($author);

        $viewer = User::factory()->create();
        $this->createFamily($viewer);

        $first = $this->makePost($author, $authorFamily, 'community', 'Hello community');
        $this->makePost($author, $authorFamily, 'community', 'Second post');
        $this->makePost($author, $authorFamily, 'family', 'Family only');

        PostLike::create(['post_id' => $first->id, 'user_id' => $viewer->id]);

        Sanctum::actingAs($viewer);

        $response = $this->getJson('/api/users/' . $author->id . '/profile')
            ->assertOk()
            ->assertJsonPath('profile.name', 'Aunt Daeng')
            ->assertJsonPath('profile.community_posts', 2)
            ->assertJsonPath('profile.likes_received', 1)
            ->assertJsonPath('profile.is_me', false)
            ->assertJsonPath('profile.is_family', false)
            ->assertJsonPath('profile.blocked', false);

        // ไม่ส่งอีเมล
        $this->assertArrayNotHasKey('email', $response->json('profile'));
        $this->assertStringNotContainsString($author->email, $response->getContent());
    }

    public function test_profile_of_commenter_is_visible(): void
    {
        $poster = User::factory()->create();
        $posterFamily = $this->createFamily($poster);

        $commenter = User::factory()->create();
        $this->createFamily($commenter);

        $viewer = User::factory()->create();
        $this->createFamily($viewer);

        $post = $this->makePost($poster, $posterFamily, 'community', 'Question');

        Comment::create([
            'post_id' => $post->id,
            'user_id' => $commenter->id,
            'content' => 'Answer',
        ]);

        Sanctum::actingAs($viewer);

        $this->getJson('/api/users/' . $commenter->id . '/profile')
            ->assertOk()
            ->assertJsonPath('profile.community_posts', 0);
    }

    // คนที่ไม่เคยอยู่ในชุมชน: คนนอกครอบครัวเปิดดูจาก id ไม่ได้
    public function test_profile_of_user_without_community_activity_is_not_found(): void
    {
        $quiet = User::factory()->create();
        $quietFamily = $this->createFamily($quiet);

        $this->makePost($quiet, $quietFamily, 'family', 'Family only');

        $hidden = $this->makePost($quiet, $quietFamily, 'community', 'Hidden post');
        $hidden->hidden_at = now();
        $hidden->save();

        $viewer = User::factory()->create();
        $this->createFamily($viewer);

        Sanctum::actingAs($viewer);

        $this->getJson('/api/users/' . $quiet->id . '/profile')
            ->assertNotFound();

        $this->postJson('/api/users/' . $quiet->id . '/report', ['reason' => 'spam'])
            ->assertNotFound();

        $this->assertSame(0, UserReport::count());
    }

    public function test_family_member_and_self_profiles_are_visible(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create();
        $this->createFamily($owner, [$member]);

        Sanctum::actingAs($owner);

        $this->getJson('/api/users/' . $member->id . '/profile')
            ->assertOk()
            ->assertJsonPath('profile.is_family', true);

        $this->getJson('/api/users/' . $owner->id . '/profile')
            ->assertOk()
            ->assertJsonPath('profile.is_me', true)
            ->assertJsonPath('profile.is_family', false);
    }

    public function test_profile_requires_family(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);
        $this->makePost($author, $family, 'community', 'Hello');

        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/users/' . $author->id . '/profile')
            ->assertForbidden();
    }

    public function test_blocked_user_profile_shows_blocked_and_hides_posts(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);
        $this->makePost($author, $family, 'community', 'Hello');

        $viewer = User::factory()->create();
        $this->createFamily($viewer);

        Sanctum::actingAs($viewer);

        $this->postJson('/api/users/' . $author->id . '/block')->assertOk();

        $this->getJson('/api/users/' . $author->id . '/profile')
            ->assertOk()
            ->assertJsonPath('profile.blocked', true)
            ->assertJsonPath('profile.community_posts', 0);

        $this->getJson('/api/posts?scope=community&user_id=' . $author->id)
            ->assertOk()
            ->assertJsonCount(0, 'posts');
    }

    // =====================================================
    // หน้าโปรไฟล์: โพสต์ที่เราเห็นได้ (ครอบครัวเดียวกัน + ชุมชน)
    // =====================================================

    public function test_family_member_profile_shows_family_and_community_posts(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create();
        $family = $this->createFamily($owner, [$member]);

        $this->makePost($member, $family, 'family', 'Member family post');
        $this->makePost($member, $family, 'community', 'Member community post');
        $this->makePost($owner, $family, 'family', 'Owner post');

        Sanctum::actingAs($owner);

        $this->getJson('/api/users/' . $member->id . '/profile')
            ->assertOk()
            ->assertJsonPath('profile.posts', 2)
            ->assertJsonPath('profile.community_posts', 1)
            ->assertJsonPath('profile.family_role', 'member');

        $contents = collect(
            $this->getJson('/api/posts?scope=user&user_id=' . $member->id)
                ->assertOk()
                ->assertJsonPath('scope', 'user')
                ->json('posts')
        )->pluck('content')->all();

        $this->assertEqualsCanonicalizing(
            ['Member family post', 'Member community post'],
            $contents
        );
    }

    public function test_outsider_sees_only_community_posts_on_profile(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);

        $this->makePost($author, $family, 'family', 'Private family post');
        $this->makePost($author, $family, 'community', 'Public post');

        $outsider = User::factory()->create();
        $this->createFamily($outsider);

        Sanctum::actingAs($outsider);

        $this->getJson('/api/users/' . $author->id . '/profile')
            ->assertOk()
            ->assertJsonPath('profile.posts', 1)
            ->assertJsonPath('profile.family_role', null);

        $contents = collect(
            $this->getJson('/api/posts?scope=user&user_id=' . $author->id)
                ->assertOk()
                ->json('posts')
        )->pluck('content')->all();

        $this->assertSame(['Public post'], $contents);

        $this->getJson('/api/posts?scope=user')->assertStatus(422);
    }

    // =====================================================
    // ฟีดชุมชนของผู้ใช้คนเดียว
    // =====================================================

    public function test_community_feed_can_filter_by_author(): void
    {
        $author = User::factory()->create();
        $authorFamily = $this->createFamily($author);

        $other = User::factory()->create();
        $otherFamily = $this->createFamily($other);

        $this->makePost($author, $authorFamily, 'community', 'Author public');
        $this->makePost($author, $authorFamily, 'family', 'Author family');
        $this->makePost($other, $otherFamily, 'community', 'Other public');

        $hidden = $this->makePost($author, $authorFamily, 'community', 'Author hidden');
        $hidden->hidden_at = now();
        $hidden->save();

        Sanctum::actingAs($other);

        $contents = collect(
            $this->getJson('/api/posts?scope=community&user_id=' . $author->id)
                ->assertOk()
                ->json('posts')
        )->pluck('content')->all();

        $this->assertSame(['Author public'], $contents);
    }

    // =====================================================
    // โพสต์ของฉัน
    // =====================================================

    public function test_my_posts_lists_own_family_and_community_posts(): void
    {
        $me = User::factory()->create();
        $relative = User::factory()->create();
        $family = $this->createFamily($me, [$relative]);

        $this->makePost($me, $family, 'family', 'My family post');
        $this->makePost($me, $family, 'community', 'My community post');
        $this->makePost($relative, $family, 'family', 'Relative post');

        $hidden = $this->makePost($me, $family, 'community', 'My hidden post');
        $hidden->hidden_at = now();
        $hidden->save();

        // โพสต์ครอบครัวเก่า (ครอบครัวอื่น) ไม่แสดง
        $oldFamily = Family::create([
            'name' => 'Old family',
            'invite_code' => 'OLD1',
            'owner_id' => $relative->id,
        ]);
        $this->makePost($me, $oldFamily, 'family', 'Old family post');

        Sanctum::actingAs($me);

        $posts = collect(
            $this->getJson('/api/posts?scope=mine')
                ->assertOk()
                ->assertJsonPath('scope', 'mine')
                ->assertJsonPath('has_more', false)
                ->json('posts')
        );

        $this->assertEqualsCanonicalizing(
            ['My family post', 'My community post', 'My hidden post'],
            $posts->pluck('content')->all()
        );

        $this->assertTrue($posts->every(fn ($post) => $post['is_mine'] === true));

        $this->assertTrue(
            $posts->firstWhere('content', 'My hidden post')['is_hidden']
        );

        // ตัวเลขในหน้าโปรไฟล์ตรงกับรายการ
        $this->getJson('/api/profile')
            ->assertOk()
            ->assertJsonPath('stats.posts', 3);
    }

    public function test_my_posts_are_paginated(): void
    {
        $me = User::factory()->create();
        $family = $this->createFamily($me);

        for ($i = 1; $i <= 21; $i++) {
            $this->makePost($me, $family, 'family', 'Post ' . $i);
        }

        Sanctum::actingAs($me);

        $this->getJson('/api/posts?scope=mine')
            ->assertOk()
            ->assertJsonCount(20, 'posts')
            ->assertJsonPath('has_more', true);

        $this->getJson('/api/posts?scope=mine&page=2')
            ->assertOk()
            ->assertJsonCount(1, 'posts')
            ->assertJsonPath('has_more', false);
    }

    public function test_profile_stats_count_likes_received(): void
    {
        $me = User::factory()->create();
        $relative = User::factory()->create();
        $family = $this->createFamily($me, [$relative]);

        $post = $this->makePost($me, $family, 'family', 'Liked post');

        PostLike::create(['post_id' => $post->id, 'user_id' => $relative->id]);

        Sanctum::actingAs($me);

        $this->getJson('/api/profile')
            ->assertOk()
            ->assertJsonPath('stats.posts', 1)
            ->assertJsonPath('stats.likes_received', 1);
    }

    // =====================================================
    // รายงานผู้ใช้
    // =====================================================

    public function test_user_can_be_reported_once(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);
        $this->makePost($author, $family, 'community', 'Spam spam');

        $reporter = User::factory()->create();
        $this->createFamily($reporter);

        Sanctum::actingAs($reporter);

        $this->postJson('/api/users/' . $author->id . '/report', [
            'reason' => 'impersonation',
            'details' => 'Pretends to be the village head',
        ])->assertOk();

        // รายงานซ้ำไม่นับเพิ่ม
        $this->postJson('/api/users/' . $author->id . '/report', [
            'reason' => 'spam',
        ])->assertOk();

        $this->assertSame(1, UserReport::count());

        $report = UserReport::first();

        $this->assertSame($author->id, $report->reported_user_id);
        $this->assertSame('impersonation', $report->reason);
    }

    public function test_user_report_validation(): void
    {
        $me = User::factory()->create();
        $family = $this->createFamily($me);
        $this->makePost($me, $family, 'community', 'Hello');

        Sanctum::actingAs($me);

        // รายงานตัวเองไม่ได้
        $this->postJson('/api/users/' . $me->id . '/report', ['reason' => 'spam'])
            ->assertStatus(422);

        $other = User::factory()->create();
        $otherFamily = $this->createFamily($other);
        $this->makePost($other, $otherFamily, 'community', 'Hi');

        $this->postJson('/api/users/' . $other->id . '/report', ['reason' => 'not-a-reason'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('reason');

        $this->assertSame(0, UserReport::count());
    }

    // =====================================================
    // Admin
    // =====================================================

    public function test_admin_sees_and_dismisses_user_reports(): void
    {
        $admin = User::factory()->create();
        $admin->is_admin = true;
        $admin->save();

        $author = User::factory()->create();
        $reporter = User::factory()->create(['name' => 'Careful Neighbor']);

        UserReport::create([
            'reported_user_id' => $author->id,
            'user_id' => $reporter->id,
            'reason' => 'harassment',
            'details' => 'Rude in comments',
        ]);

        $this->actingAs($admin);

        Livewire::test(ViewUser::class, ['record' => $author->getRouteKey()])
            ->assertSee('ด่าทอ / คุกคาม')
            ->assertSee('Careful Neighbor')
            ->assertSee('Rude in comments');

        Livewire::test(ListUsers::class)
            ->callAction(TestAction::make('dismissReports')->table($author));

        $this->assertSame(0, $author->reportsReceived()->count());
    }

    public function test_deleting_account_removes_reports(): void
    {
        $author = User::factory()->create();
        $reporter = User::factory()->create();

        UserReport::create([
            'reported_user_id' => $author->id,
            'user_id' => $reporter->id,
            'reason' => 'spam',
        ]);

        $author->delete();

        $this->assertSame(0, UserReport::count());
    }
}
