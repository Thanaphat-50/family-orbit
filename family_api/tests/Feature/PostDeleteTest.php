<?php

namespace Tests\Feature;

use App\Models\Comment;
use App\Models\Family;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PostDeleteTest extends TestCase
{
    use RefreshDatabase;

    // =====================================================
    // สร้างครอบครัวพร้อมสมาชิก
    // =====================================================

    private function createFamily(User $owner, array $members = []): Family
    {
        $family = Family::create([
            'name' => 'Family ' . $owner->id,
            'invite_code' => 'CODE' . $owner->id,
            'owner_id' => $owner->id,
        ]);

        FamilyMember::create([
            'family_id' => $family->id,
            'user_id' => $owner->id,
            'role' => 'owner',
        ]);

        foreach ($members as $member) {
            FamilyMember::create([
                'family_id' => $family->id,
                'user_id' => $member->id,
                'role' => 'member',
            ]);
        }

        return $family;
    }

    // =====================================================
    // GET /api/posts: บอกว่าโพสต์ไหนเป็นของเรา
    // =====================================================

    public function test_posts_index_marks_own_posts(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $family = $this->createFamily($mom, [$dad]);

        Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'content' => 'Mom post',
        ]);

        Post::create([
            'family_id' => $family->id,
            'user_id' => $dad->id,
            'content' => 'Dad post',
        ]);

        $response = $this->actingAs($mom)
            ->getJson('/api/posts')
            ->assertOk()
            ->assertJsonPath('current_user.id', $mom->id);

        $isMineByContent = collect($response->json('posts'))
            ->pluck('is_mine', 'content');

        $this->assertTrue($isMineByContent['Mom post']);
        $this->assertFalse($isMineByContent['Dad post']);
    }

    // =====================================================
    // เจ้าของโพสต์ลบได้ และความคิดเห็นถูกลบตามไปด้วย
    // =====================================================

    public function test_owner_can_delete_own_post_with_comments(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $family = $this->createFamily($mom, [$dad]);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'content' => 'Dinner at 7',
        ]);

        Comment::create([
            'post_id' => $post->id,
            'user_id' => $dad->id,
            'content' => 'OK',
        ]);

        $this->actingAs($mom)
            ->deleteJson('/api/posts/' . $post->id)
            ->assertOk()
            ->assertJson(['status' => true]);

        $this->assertDatabaseMissing('posts', ['id' => $post->id]);
        $this->assertDatabaseMissing('comments', ['post_id' => $post->id]);
    }

    // =====================================================
    // สมาชิกคนอื่นในครอบครัวลบโพสต์ของเราไม่ได้
    // =====================================================

    public function test_other_member_cannot_delete_post(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $family = $this->createFamily($mom, [$dad]);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'content' => 'Mom post',
        ]);

        $this->actingAs($dad)
            ->deleteJson('/api/posts/' . $post->id)
            ->assertForbidden();

        $this->assertDatabaseHas('posts', ['id' => $post->id]);
    }

    // =====================================================
    // ต้องเข้าสู่ระบบก่อนจึงจะลบได้
    // =====================================================

    public function test_guest_cannot_delete_post(): void
    {
        $mom = User::factory()->create();

        $family = $this->createFamily($mom);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'content' => 'Mom post',
        ]);

        $this->deleteJson('/api/posts/' . $post->id)
            ->assertUnauthorized();

        $this->assertDatabaseHas('posts', ['id' => $post->id]);
    }
}
