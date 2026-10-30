<?php

namespace Tests\Feature;

use App\Models\Comment;
use App\Models\Post;
use App\Models\PostReport;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class PostShowTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    // =====================================================
    // โพสต์ครอบครัว: เห็นเฉพาะคนในครอบครัว
    // =====================================================

    public function test_family_post_is_visible_only_to_family(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();
        $neighbor = User::factory()->create();

        $family = $this->createFamily($mom, [$dad]);
        $this->createFamily($neighbor);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'content' => 'Dinner at 7',
        ]);

        Comment::create(['post_id' => $post->id, 'user_id' => $dad->id, 'content' => 'OK']);

        Sanctum::actingAs($dad);

        $this->getJson("/api/posts/{$post->id}")
            ->assertOk()
            ->assertJsonPath('post.content', 'Dinner at 7')
            ->assertJsonPath('post.is_mine', false)
            ->assertJsonPath('post.likes_count', 0)
            ->assertJsonCount(1, 'post.comments')
            ->assertJsonPath('current_user.id', $dad->id);

        Sanctum::actingAs($neighbor);

        $this->getJson("/api/posts/{$post->id}")->assertNotFound();
    }

    // =====================================================
    // โพสต์ชุมชน: ใช้กฎเดียวกับฟีด
    // =====================================================

    public function test_community_post_follows_feed_rules(): void
    {
        $author = User::factory()->create();
        $viewer = User::factory()->create();
        $troll = User::factory()->create();

        $family = $this->createFamily($author);
        $this->createFamily($viewer);
        $this->createFamily($troll);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'category' => 'general',
            'content' => 'Hello neighbors',
        ]);

        Comment::create(['post_id' => $post->id, 'user_id' => $author->id, 'content' => 'Welcome']);
        Comment::create(['post_id' => $post->id, 'user_id' => $troll->id, 'content' => 'Spam']);

        $viewer->blockedUsers()->attach($troll->id);

        Sanctum::actingAs($viewer);

        // ความคิดเห็นของคนที่เราบล็อกไม่แสดง
        $this->getJson("/api/posts/{$post->id}")
            ->assertOk()
            ->assertJsonCount(1, 'post.comments')
            ->assertJsonPath('post.comments.0.content', 'Welcome');

        // รายงานแล้ว → ไม่เห็นอีก
        PostReport::create(['post_id' => $post->id, 'user_id' => $viewer->id, 'reason' => 'spam']);

        $this->getJson("/api/posts/{$post->id}")->assertNotFound();
    }

    public function test_hidden_or_blocked_community_post_is_not_found(): void
    {
        $author = User::factory()->create();
        $viewer = User::factory()->create();

        $family = $this->createFamily($author);
        $this->createFamily($viewer);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'content' => 'Hidden soon',
        ]);

        Sanctum::actingAs($viewer);

        $this->getJson("/api/posts/{$post->id}")->assertOk();

        $viewer->blockedUsers()->attach($author->id);

        $this->getJson("/api/posts/{$post->id}")->assertNotFound();

        $viewer->blockedUsers()->detach($author->id);

        $post->hidden_at = now();
        $post->save();

        $this->getJson("/api/posts/{$post->id}")->assertNotFound();
    }

    // ยังไม่มีครอบครัว: เปิดโพสต์ชุมชนได้ แต่โพสต์ครอบครัวไม่ได้
    public function test_user_without_family_sees_only_community_posts(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'content' => 'Hi',
        ]);

        $private = Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'family',
            'content' => 'Home',
        ]);

        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/posts/{$post->id}")->assertOk();
        $this->getJson("/api/posts/{$private->id}")->assertForbidden();
    }
}
