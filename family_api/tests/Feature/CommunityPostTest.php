<?php

namespace Tests\Feature;

use App\Models\Comment;
use App\Models\Family;
use App\Models\Post;
use App\Models\PostReport;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class CommunityPostTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function communityPost(
        User $author,
        Family $family,
        string $content = 'Hello community'
    ): Post {
        return Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'content' => $content,
        ]);
    }

    private function familyPost(
        User $author,
        Family $family,
        string $content = 'Family only'
    ): Post {
        return Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'content' => $content,
        ]);
    }

    private function contents($response): array
    {
        return collect($response->json('posts'))
            ->pluck('content')
            ->all();
    }

    // =====================================================
    // ฟีดครอบครัว กับ ฟีดชุมชน แยกกัน และไม่ส่ง email
    // =====================================================

    public function test_family_and_community_feeds_are_separated(): void
    {
        $mom = User::factory()->create();
        $neighbor = User::factory()->create([
            'email' => 'neighbor@example.com',
        ]);

        $momFamily = $this->createFamily($mom);
        $otherFamily = $this->createFamily($neighbor);

        $this->familyPost($mom, $momFamily, 'Family only');
        $this->communityPost($neighbor, $otherFamily, 'Hello from next door');

        Sanctum::actingAs($mom);

        $family = $this->getJson('/api/posts')->assertOk();

        $this->assertSame(['Family only'], $this->contents($family));

        $community = $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonPath('has_more', false);

        $this->assertSame(['Hello from next door'], $this->contents($community));

        $this->assertStringNotContainsString(
            'neighbor@example.com',
            $community->getContent()
        );
    }

    // =====================================================
    // โพสต์ชุมชนต้องยอมรับกฎก่อน และไม่สร้างแจ้งเตือน
    // =====================================================

    public function test_community_post_requires_accepting_terms(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $this->createFamily($mom, [$dad]);

        Sanctum::actingAs($mom);

        $this->getJson('/api/posts')
            ->assertJsonPath('current_user.community_terms_accepted', false);

        $this->postJson('/api/posts', [
            'content' => 'Hi everyone',
            'visibility' => 'community',
        ])
            ->assertForbidden()
            ->assertJsonPath('code', 'terms_required');

        $this->postJson('/api/community/accept-terms')->assertOk();

        $this->postJson('/api/posts', [
            'content' => 'Hi everyone',
            'visibility' => 'community',
        ])
            ->assertCreated()
            ->assertJsonPath('post.visibility', 'community');

        $this->getJson('/api/posts')
            ->assertJsonPath('current_user.community_terms_accepted', true);

        // โพสต์ชุมชนไม่แจ้งเตือนคนในครอบครัว
        $this->assertDatabaseCount('app_notifications', 0);
    }

    // =====================================================
    // คนต่างครอบครัวแสดงความคิดเห็นได้เฉพาะโพสต์ชุมชน
    // =====================================================

    public function test_other_family_can_comment_only_on_community_posts(): void
    {
        $mom = User::factory()->create();
        $neighbor = User::factory()->create();

        $momFamily = $this->createFamily($mom);
        $this->createFamily($neighbor);

        $communityPost = $this->communityPost($mom, $momFamily);
        $familyPost = $this->familyPost($mom, $momFamily);

        Sanctum::actingAs($neighbor);

        $this->postJson('/api/posts/' . $communityPost->id . '/comments', [
            'content' => 'Nice!',
        ])->assertCreated();

        $this->postJson('/api/posts/' . $familyPost->id . '/comments', [
            'content' => 'Hello',
        ])->assertForbidden();

        // เจ้าของโพสต์ได้รับแจ้งเตือน โดยไม่ผูกกับครอบครัว
        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $mom->id,
            'type' => 'new_comment',
            'family_id' => null,
        ]);
    }

    // =====================================================
    // รายงานครบ 3 คน → ซ่อนอัตโนมัติ
    // =====================================================

    public function test_post_is_hidden_after_three_reports(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);

        $post = $this->communityPost($author, $family);
        $familyPost = $this->familyPost($author, $family);

        // รายงานโพสต์ตัวเองไม่ได้
        Sanctum::actingAs($author);

        $this->postJson('/api/posts/' . $post->id . '/report', [
            'reason' => 'spam',
        ])->assertStatus(422);

        $reporters = User::factory()->count(3)->create();

        foreach ($reporters as $index => $reporter) {
            $this->createFamily($reporter);

            Sanctum::actingAs($reporter);

            $this->postJson('/api/posts/' . $post->id . '/report', [
                'reason' => 'spam',
            ])->assertOk();

            if ($index === 0) {
                // คนที่รายงานแล้วจะไม่เห็นโพสต์นั้นในฟีดอีก
                $this->getJson('/api/posts?scope=community')
                    ->assertJsonCount(0, 'posts');

                // รายงานซ้ำไม่นับเพิ่ม
                $this->postJson('/api/posts/' . $post->id . '/report', [
                    'reason' => 'scam',
                ])->assertOk();

                $this->assertSame(1, PostReport::count());
                $this->assertNull($post->fresh()->hidden_at);

                // รายงานได้เฉพาะโพสต์ชุมชน
                $this->postJson('/api/posts/' . $familyPost->id . '/report', [
                    'reason' => 'spam',
                ])->assertStatus(422);
            }
        }

        $this->assertNotNull($post->fresh()->hidden_at);

        Sanctum::actingAs($author);

        $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonCount(0, 'posts');
    }

    // =====================================================
    // บล็อกแล้วไม่เห็นโพสต์และความคิดเห็นของคนนั้น
    // =====================================================

    public function test_blocked_user_posts_and_comments_are_hidden(): void
    {
        $me = User::factory()->create();
        $troll = User::factory()->create();
        $friend = User::factory()->create();

        $this->createFamily($me);
        $trollFamily = $this->createFamily($troll);
        $friendFamily = $this->createFamily($friend);

        $this->communityPost($troll, $trollFamily, 'Troll post');
        $friendPost = $this->communityPost($friend, $friendFamily, 'Friend post');

        Comment::create([
            'post_id' => $friendPost->id,
            'user_id' => $troll->id,
            'content' => 'Troll comment',
        ]);

        Sanctum::actingAs($me);

        $this->postJson('/api/users/' . $me->id . '/block')
            ->assertStatus(422);

        $this->postJson('/api/users/' . $troll->id . '/block')
            ->assertOk();

        $feed = $this->getJson('/api/posts?scope=community')->assertOk();

        $this->assertSame(['Friend post'], $this->contents($feed));
        $this->assertCount(0, $feed->json('posts.0.comments'));

        $this->getJson('/api/blocks')
            ->assertOk()
            ->assertJsonPath('users.0.id', $troll->id);

        $this->deleteJson('/api/users/' . $troll->id . '/block')
            ->assertOk();

        $feed = $this->getJson('/api/posts?scope=community')->assertOk();

        $this->assertEqualsCanonicalizing(
            ['Friend post', 'Troll post'],
            $this->contents($feed)
        );
    }

    // =====================================================
    // เจ้าของลบโพสต์ชุมชนได้ แม้ออกจากครอบครัวแล้ว
    // =====================================================

    public function test_author_can_delete_community_post_after_leaving_family(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create();

        $family = $this->createFamily($owner, [$member]);

        $post = $this->communityPost($member, $family);

        Sanctum::actingAs($member);

        $this->postJson('/api/families/leave')->assertOk();

        $this->deleteJson('/api/posts/' . $post->id)->assertOk();

        $this->assertDatabaseMissing('posts', ['id' => $post->id]);
    }

    // =====================================================
    // ฟีดชุมชนแบ่งหน้า หน้าละ 20 โพสต์
    // =====================================================

    public function test_community_feed_is_paginated(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);

        for ($i = 1; $i <= 21; $i++) {
            $this->communityPost($author, $family, 'Post ' . $i);
        }

        Sanctum::actingAs($author);

        $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonCount(20, 'posts')
            ->assertJsonPath('has_more', true);

        $this->getJson('/api/posts?scope=community&page=2')
            ->assertOk()
            ->assertJsonCount(1, 'posts')
            ->assertJsonPath('has_more', false);
    }
}
