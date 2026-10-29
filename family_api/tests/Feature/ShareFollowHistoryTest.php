<?php

namespace Tests\Feature;

use App\Models\Comment;
use App\Models\Interaction;
use App\Models\Post;
use App\Models\User;
use App\Services\AccountDeletionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class ShareFollowHistoryTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function member(): User
    {
        $user = User::factory()->create(['community_terms_accepted_at' => now()]);

        $this->createFamily($user);

        return $user;
    }

    private function communityPost(User $author, string $content = 'สูตรแกงเขียวหวาน'): Post
    {
        return Post::create([
            'family_id' => \App\Models\FamilyMember::where('user_id', $author->id)->value('family_id'),
            'user_id' => $author->id,
            'visibility' => 'community',
            'category' => 'qa',
            'content' => $content,
        ]);
    }

    // =====================================================
    // แชร์
    // =====================================================

    public function test_share_to_community_creates_a_repost_with_the_original(): void
    {
        $author = $this->member();
        $sharer = $this->member();

        $post = $this->communityPost($author);

        Sanctum::actingAs($sharer);

        $repostId = $this->postJson("/api/posts/{$post->id}/share", [
            'channel' => 'community',
            'content' => 'น่าลอง',
        ])
            ->assertCreated()
            ->assertJsonPath('shares_count', 1)
            ->assertJsonPath('post.shared_post.id', $post->id)
            ->assertJsonPath('post.shared_post.user.id', $author->id)
            ->assertJsonPath('post.category', 'qa')
            ->json('post.id');

        $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonPath('posts.0.id', $repostId)
            ->assertJsonPath('posts.0.content', 'น่าลอง')
            ->assertJsonPath('posts.0.shared_post.content', 'สูตรแกงเขียวหวาน')
            ->assertJsonPath('posts.1.id', $post->id)
            ->assertJsonPath('posts.1.shares_count', 1);

        // แชร์ต่อจากโพสต์ที่แชร์มา → ยังอ้างถึงต้นฉบับ
        $third = $this->member();

        Sanctum::actingAs($third);

        $this->postJson("/api/posts/{$repostId}/share", ['channel' => 'external'])
            ->assertOk()
            ->assertJsonPath('post_id', $post->id)
            ->assertJsonPath('shares_count', 2);
    }

    public function test_share_to_family_notifies_family_and_shows_in_family_feed(): void
    {
        $author = $this->member();

        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $this->createFamily($mom, [$dad]);

        $post = $this->communityPost($author);

        Sanctum::actingAs($mom);

        $this->postJson("/api/posts/{$post->id}/share", ['channel' => 'family'])
            ->assertCreated()
            ->assertJsonPath('post.visibility', 'family');

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $dad->id,
            'type' => 'new_post',
        ]);

        Sanctum::actingAs($dad);

        $this->getJson('/api/posts?scope=family')
            ->assertOk()
            ->assertJsonPath('posts.0.shared_post.id', $post->id);
    }

    public function test_family_posts_cannot_be_shared(): void
    {
        $mom = $this->member();

        $post = Post::create([
            'family_id' => \App\Models\FamilyMember::where('user_id', $mom->id)->value('family_id'),
            'user_id' => $mom->id,
            'visibility' => 'family',
            'content' => 'เรื่องในบ้าน',
        ]);

        Sanctum::actingAs($mom);

        $this->postJson("/api/posts/{$post->id}/share", ['channel' => 'external'])->assertNotFound();
        $this->postJson("/api/posts/{$post->id}/share", ['channel' => 'twitter'])->assertStatus(422);

        $this->assertSame(0, Interaction::count());
    }

    public function test_deleted_original_shows_as_unavailable(): void
    {
        $author = $this->member();
        $sharer = $this->member();

        $post = $this->communityPost($author);

        Sanctum::actingAs($sharer);

        $repostId = $this->postJson("/api/posts/{$post->id}/share", ['channel' => 'community'])
            ->json('post.id');

        $post->delete();

        $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonPath('posts.0.id', $repostId)
            ->assertJsonPath('posts.0.shared_post', null)
            ->assertJsonPath('posts.0.shared_post_unavailable', true);
    }

    public function test_community_share_needs_community_terms(): void
    {
        $author = $this->member();

        $newbie = User::factory()->create();
        $this->createFamily($newbie);

        $post = $this->communityPost($author);

        Sanctum::actingAs($newbie);

        $this->postJson("/api/posts/{$post->id}/share", ['channel' => 'community'])
            ->assertForbidden()
            ->assertJsonPath('code', 'terms_required');

        // ส่งต่อไปแอปอื่นได้
        $this->postJson("/api/posts/{$post->id}/share", ['channel' => 'external'])->assertOk();
    }

    // =====================================================
    // ประวัติการใช้งาน
    // =====================================================

    public function test_history_records_likes_comments_shares_and_follows(): void
    {
        $author = $this->member();
        $me = $this->member();

        $post = $this->communityPost($author);

        Sanctum::actingAs($me);

        $this->postJson("/api/posts/{$post->id}/like")->assertOk();
        $this->postJson("/api/posts/{$post->id}/comments", ['content' => 'ขอบคุณสูตรค่ะ'])->assertCreated();
        $this->postJson("/api/posts/{$post->id}/share", ['channel' => 'external'])->assertOk();
        $this->postJson("/api/users/{$author->id}/follow")->assertOk();

        $this->getJson('/api/me/history')
            ->assertOk()
            ->assertJsonCount(4, 'items')
            ->assertJsonPath('items.0.type', 'follow')
            ->assertJsonPath('items.0.target_user.id', $author->id)
            ->assertJsonPath('items.1.type', 'share')
            ->assertJsonPath('items.1.channel', 'external')
            ->assertJsonPath('items.2.type', 'comment')
            ->assertJsonPath('items.2.excerpt', 'ขอบคุณสูตรค่ะ')
            ->assertJsonPath('items.3.type', 'like')
            ->assertJsonPath('items.3.post.id', $post->id);

        // ยกเลิกถูกใจ / ลบความคิดเห็น → หายจากประวัติ
        $this->postJson("/api/posts/{$post->id}/like")->assertOk();

        $comment = Comment::first();

        $this->deleteJson("/api/comments/{$comment->id}")->assertOk();

        $this->getJson('/api/me/history')->assertJsonCount(2, 'items');

        // คนอื่นไม่เห็นประวัติของเรา
        Sanctum::actingAs($author);

        $this->getJson('/api/me/history')->assertJsonCount(0, 'items');

        Sanctum::actingAs($me);

        $this->deleteJson('/api/me/history')->assertOk();

        $this->getJson('/api/me/history')->assertJsonCount(0, 'items');

        // ล้างประวัติแล้ว การติดตามจริงยังอยู่
        $this->assertTrue($me->following()->whereKey($author->id)->exists());
    }

    // =====================================================
    // ติดตาม
    // =====================================================

    public function test_follow_and_unfollow_with_profile_counts(): void
    {
        $author = $this->member();
        $me = $this->member();

        Sanctum::actingAs($me);

        $this->communityPost($author);

        $this->postJson("/api/users/{$author->id}/follow")
            ->assertOk()
            ->assertJsonPath('is_following', true)
            ->assertJsonPath('followers_count', 1);

        // กดซ้ำไม่ซ้ำ
        $this->postJson("/api/users/{$author->id}/follow")->assertJsonPath('followers_count', 1);

        $this->getJson("/api/users/{$author->id}/profile")
            ->assertOk()
            ->assertJsonPath('profile.is_following', true)
            ->assertJsonPath('profile.followers_count', 1)
            ->assertJsonPath('profile.following_count', 0);

        $this->deleteJson("/api/users/{$author->id}/follow")
            ->assertOk()
            ->assertJsonPath('is_following', false)
            ->assertJsonPath('followers_count', 0);

        $this->postJson("/api/users/{$me->id}/follow")->assertStatus(422);
    }

    public function test_cannot_follow_when_blocked(): void
    {
        $author = $this->member();
        $me = $this->member();

        $author->blockedUsers()->attach($me->id);

        Sanctum::actingAs($me);

        $this->postJson("/api/users/{$author->id}/follow")->assertForbidden();
    }

    public function test_deleting_an_account_removes_its_history_and_follows(): void
    {
        $author = $this->member();
        $me = $this->member();

        $post = $this->communityPost($author);

        Sanctum::actingAs($me);

        $this->postJson("/api/posts/{$post->id}/like")->assertOk();
        $this->postJson("/api/users/{$author->id}/follow")->assertOk();

        app(AccountDeletionService::class)->delete($me->fresh());

        $this->assertSame(0, Interaction::count());
        $this->assertDatabaseCount('follows', 0);
    }
}
