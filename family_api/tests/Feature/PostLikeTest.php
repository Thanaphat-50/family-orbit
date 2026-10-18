<?php

namespace Tests\Feature;

use App\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class PostLikeTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    // =====================================================
    // กดถูกใจ → กดซ้ำ = ยกเลิก และฟีดแสดงข้อมูลถูกต้อง
    // =====================================================

    public function test_like_toggles_and_feed_shows_counts(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();
        $family = $this->createFamily($mom, [$dad]);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'content' => 'Dinner at 7',
        ]);

        Sanctum::actingAs($dad);

        $this->postJson('/api/posts/' . $post->id . '/like')
            ->assertOk()
            ->assertJson(['liked' => true, 'likes_count' => 1]);

        $this->getJson('/api/posts')
            ->assertJsonPath('posts.0.likes_count', 1)
            ->assertJsonPath('posts.0.liked_by_me', true);

        $this->postJson('/api/posts/' . $post->id . '/like')
            ->assertOk()
            ->assertJson(['liked' => false, 'likes_count' => 0]);

        $this->getJson('/api/posts')
            ->assertJsonPath('posts.0.likes_count', 0)
            ->assertJsonPath('posts.0.liked_by_me', false);
    }

    // =====================================================
    // คนนอกครอบครัวถูกใจโพสต์ครอบครัวไม่ได้
    // แต่ถูกใจโพสต์ชุมชนได้
    // =====================================================

    public function test_outsider_can_like_only_community_posts(): void
    {
        $mom = User::factory()->create();
        $neighbor = User::factory()->create();
        $family = $this->createFamily($mom);
        $this->createFamily($neighbor);

        $familyPost = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'content' => 'Family only',
        ]);

        $communityPost = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'visibility' => 'community',
            'content' => 'Hello neighbors',
        ]);

        Sanctum::actingAs($neighbor);

        $this->postJson('/api/posts/' . $familyPost->id . '/like')
            ->assertForbidden();

        $this->postJson('/api/posts/' . $communityPost->id . '/like')
            ->assertOk()
            ->assertJson(['liked' => true]);

        $this->getJson('/api/posts?scope=community')
            ->assertJsonPath('posts.0.likes_count', 1)
            ->assertJsonPath('posts.0.liked_by_me', true);
    }

    // =====================================================
    // โพสต์ที่ถูกซ่อนถูกใจไม่ได้
    // =====================================================

    public function test_cannot_like_hidden_community_post(): void
    {
        $author = User::factory()->create();
        $viewer = User::factory()->create();
        $family = $this->createFamily($author);
        $this->createFamily($viewer);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'content' => 'Hidden post',
        ]);

        $post->hidden_at = now();
        $post->save();

        Sanctum::actingAs($viewer);

        $this->postJson('/api/posts/' . $post->id . '/like')
            ->assertForbidden();
    }
}
