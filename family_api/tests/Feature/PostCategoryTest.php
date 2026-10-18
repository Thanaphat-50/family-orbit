<?php

namespace Tests\Feature;

use App\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class PostCategoryTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function acceptedUser(): User
    {
        $user = User::factory()->create();

        $user->forceFill([
            'community_terms_accepted_at' => now(),
        ])->save();

        return $user;
    }

    // =====================================================
    // โพสต์ชุมชนเก็บหมวด (ไม่ส่งมา = general)
    // โพสต์ครอบครัวไม่เก็บหมวด
    // =====================================================

    public function test_store_saves_category_only_for_community_posts(): void
    {
        $user = $this->acceptedUser();
        $this->createFamily($user);

        Sanctum::actingAs($user);

        $this->postJson('/api/posts', [
            'content' => 'Anyone know a good plumber?',
            'visibility' => 'community',
            'category' => 'qa',
        ])
            ->assertCreated()
            ->assertJsonPath('post.category', 'qa');

        $this->postJson('/api/posts', [
            'content' => 'Hello everyone',
            'visibility' => 'community',
        ])
            ->assertCreated()
            ->assertJsonPath('post.category', 'general');

        $this->postJson('/api/posts', [
            'content' => 'Dinner at 7',
            'category' => 'news',
        ])
            ->assertCreated()
            ->assertJsonPath('post.category', null);
    }

    public function test_invalid_category_is_rejected(): void
    {
        $user = $this->acceptedUser();
        $this->createFamily($user);

        Sanctum::actingAs($user);

        $this->postJson('/api/posts', [
            'content' => 'Buy my stuff',
            'visibility' => 'community',
            'category' => 'ads',
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('category');

        $this->getJson('/api/posts?scope=community&category=ads')
            ->assertStatus(422);

        $this->assertSame(0, Post::count());
    }

    // =====================================================
    // กรองฟีดชุมชนตามหมวด
    // =====================================================

    public function test_community_feed_filters_by_category(): void
    {
        $author = User::factory()->create();
        $viewer = User::factory()->create();
        $family = $this->createFamily($author);
        $this->createFamily($viewer);

        foreach (['qa' => 'Question', 'event' => 'Party', 'general' => 'Hi'] as $category => $content) {
            Post::create([
                'family_id' => $family->id,
                'user_id' => $author->id,
                'visibility' => 'community',
                'category' => $category,
                'content' => $content,
            ]);
        }

        Sanctum::actingAs($viewer);

        $this->getJson('/api/posts?scope=community&category=qa')
            ->assertOk()
            ->assertJsonPath('category', 'qa')
            ->assertJsonCount(1, 'posts')
            ->assertJsonPath('posts.0.content', 'Question');

        $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonPath('category', null)
            ->assertJsonCount(3, 'posts');
    }
}
