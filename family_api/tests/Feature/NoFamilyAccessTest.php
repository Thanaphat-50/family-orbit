<?php

namespace Tests\Feature;

use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

// ยังไม่มีครอบครัว: ดูหน้าหลัก (ชุมชน) และตลาดได้
// โพสต์ / แชร์ในแอป / ฟีดครอบครัว ต้องมีครอบครัว
class NoFamilyAccessTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function posts(): array
    {
        $author = User::factory()->create(['community_terms_accepted_at' => now()]);

        $family = $this->createFamily($author);

        $community = Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'category' => 'general',
            'content' => 'สวัสดีชุมชน',
        ]);

        $private = Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'family',
            'content' => 'เรื่องในบ้าน',
        ]);

        return [$author, $community, $private];
    }

    public function test_can_browse_and_react_to_the_community(): void
    {
        [$author, $community, $private] = $this->posts();

        $newcomer = User::factory()->create(['community_terms_accepted_at' => now()]);

        Sanctum::actingAs($newcomer);

        $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonPath('posts.0.id', $community->id);

        $this->getJson('/api/posts?scope=community&sort=for_you')
            ->assertOk()
            ->assertJsonCount(1, 'posts');

        $this->getJson("/api/posts/{$community->id}")->assertOk();

        $this->postJson("/api/posts/{$community->id}/like")
            ->assertOk()
            ->assertJsonPath('liked', true);

        $this->postJson("/api/posts/{$community->id}/comments", ['content' => 'ยินดีที่ได้รู้จัก'])
            ->assertCreated();

        $this->getJson("/api/users/{$author->id}/profile")
            ->assertOk()
            ->assertJsonPath('profile.is_family', false);

        $this->getJson("/api/posts?scope=user&user_id={$author->id}")
            ->assertOk()
            ->assertJsonCount(1, 'posts');

        $this->postJson("/api/users/{$author->id}/follow")->assertOk();

        $this->postJson("/api/posts/{$community->id}/share", ['channel' => 'external'])->assertOk();

        $this->getJson('/api/market/products')->assertOk();

        // เรื่องในครอบครัวของคนอื่นยังเห็นไม่ได้
        $this->getJson("/api/posts/{$private->id}")->assertForbidden();
        $this->postJson("/api/posts/{$private->id}/like")->assertForbidden();
        $this->postJson("/api/posts/{$private->id}/comments", ['content' => 'x'])->assertForbidden();
    }

    public function test_posting_and_in_app_sharing_need_a_family(): void
    {
        [, $community] = $this->posts();

        $newcomer = User::factory()->create(['community_terms_accepted_at' => now()]);

        Sanctum::actingAs($newcomer);

        $this->postJson('/api/posts', ['content' => 'โพสต์แรก', 'visibility' => 'community'])
            ->assertForbidden()
            ->assertJsonPath('code', 'family_required');

        $this->postJson("/api/posts/{$community->id}/share", ['channel' => 'community'])
            ->assertForbidden()
            ->assertJsonPath('code', 'family_required');

        $this->getJson('/api/posts?scope=family')->assertForbidden();
        $this->getJson('/api/posts?scope=mine')->assertForbidden();

        $this->assertSame(0, FamilyMember::where('user_id', $newcomer->id)->count());
    }
}
