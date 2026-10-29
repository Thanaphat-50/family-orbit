<?php

namespace Tests\Feature;

use App\Models\FamilyMember;
use App\Models\Interaction;
use App\Models\Post;
use App\Models\PostLike;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class ForYouFeedTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function member(): User
    {
        $user = User::factory()->create(['community_terms_accepted_at' => now()]);

        $this->createFamily($user);

        return $user;
    }

    private function makePost(User $author, string $category, int $hoursAgo = 0, string $content = 'โพสต์'): Post
    {
        $post = Post::create([
            'family_id' => FamilyMember::where('user_id', $author->id)->value('family_id'),
            'user_id' => $author->id,
            'visibility' => 'community',
            'category' => $category,
            'content' => $content,
        ]);

        $post->forceFill([
            'created_at' => now()->subHours($hoursAgo),
            'updated_at' => now()->subHours($hoursAgo),
        ])->save();

        return $post;
    }

    private function like(User $user, Post $post): void
    {
        PostLike::create(['post_id' => $post->id, 'user_id' => $user->id]);

        Interaction::record($user, Interaction::LIKE, $post);
    }

    public function test_for_you_puts_my_interests_and_followed_people_first(): void
    {
        $me = $this->member();
        $cook = $this->member();
        $friend = $this->member();
        $other = $this->member();

        // ประวัติ: เราชอบหมวดถาม-ตอบ
        $old = $this->makePost($cook, 'qa', 48);
        $this->like($me, $old);

        $me->following()->attach($friend->id);

        $qa = $this->makePost($cook, 'qa', 5, 'ถามสูตรอาหาร');
        $fromFriend = $this->makePost($friend, 'general', 6, 'จากคนที่ติดตาม');
        $newest = $this->makePost($other, 'news', 1, 'ข่าวใหม่สุด');

        Sanctum::actingAs($me);

        $ids = collect($this->getJson('/api/posts?scope=community&sort=for_you')
            ->assertOk()
            ->assertJsonPath('sort', 'for_you')
            ->json('posts'))->pluck('id')->all();

        $this->assertLessThan(array_search($newest->id, $ids), array_search($qa->id, $ids));
        $this->assertLessThan(array_search($newest->id, $ids), array_search($fromFriend->id, $ids));

        // แท็บ "ล่าสุด" ยังเรียงตามเวลาเหมือนเดิม
        $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonPath('posts.0.id', $newest->id);
    }

    public function test_for_you_pages_do_not_repeat_posts(): void
    {
        $me = $this->member();
        $author = $this->member();

        foreach (range(1, 25) as $i) {
            $this->makePost($author, 'general', $i);
        }

        Sanctum::actingAs($me);

        $first = $this->getJson('/api/posts?scope=community&sort=for_you')
            ->assertOk()
            ->assertJsonCount(20, 'posts')
            ->assertJsonPath('has_more', true)
            ->json('posts.*.id');

        // ระหว่างเลื่อน มีโพสต์ใหม่เข้ามา → หน้า 2 ยังใช้ลำดับเดิม
        $this->makePost($author, 'general', 0);

        $second = $this->getJson('/api/posts?scope=community&sort=for_you&page=2')
            ->assertOk()
            ->assertJsonCount(5, 'posts')
            ->assertJsonPath('has_more', false)
            ->json('posts.*.id');

        $this->assertSame([], array_intersect($first, $second));
    }

    public function test_hidden_and_blocked_posts_stay_out_of_for_you(): void
    {
        $me = $this->member();
        $author = $this->member();
        $blocked = $this->member();

        $hidden = $this->makePost($author, 'general', 1);
        $hidden->forceFill(['hidden_at' => now()])->save();

        $this->makePost($blocked, 'general', 1);
        $visible = $this->makePost($author, 'general', 2);

        $me->blockedUsers()->attach($blocked->id);

        Sanctum::actingAs($me);

        $this->getJson('/api/posts?scope=community&sort=for_you')
            ->assertOk()
            ->assertJsonCount(1, 'posts')
            ->assertJsonPath('posts.0.id', $visible->id);
    }

    // =====================================================
    // แนะนำคนที่ชอบคล้ายกัน
    // =====================================================

    public function test_suggests_people_who_like_the_same_posts(): void
    {
        $me = $this->member();
        $author = $this->member();
        $twin = $this->member();
        $stranger = $this->member();

        $a = $this->makePost($author, 'qa', 3);
        $b = $this->makePost($author, 'qa', 4);

        $this->like($me, $a);
        $this->like($me, $b);
        $this->like($twin, $a);
        $this->like($twin, $b);

        // คนในครอบครัวเดียวกันไม่ต้องแนะนำ
        $sister = User::factory()->create();
        FamilyMember::create([
            'family_id' => FamilyMember::where('user_id', $me->id)->value('family_id'),
            'user_id' => $sister->id,
            'role' => 'member',
        ]);
        $this->like($sister, $a);

        Sanctum::actingAs($me);

        $users = collect($this->getJson('/api/users/suggestions')->assertOk()->json('users'));

        $this->assertSame($twin->id, $users->first()['id']);
        $this->assertSame('ชอบโพสต์เดียวกับคุณ 2 โพสต์', $users->first()['reason']);
        $this->assertTrue($users->pluck('id')->contains($author->id));
        $this->assertFalse($users->pluck('id')->contains($sister->id));
        $this->assertFalse($users->pluck('id')->contains($stranger->id));
        $this->assertFalse($users->pluck('id')->contains($me->id));

        // ติดตามแล้ว → ไม่แนะนำซ้ำ
        $this->postJson("/api/users/{$twin->id}/follow")->assertOk();

        $this->assertFalse(
            collect($this->getJson('/api/users/suggestions')->json('users'))->pluck('id')->contains($twin->id)
        );
    }

    public function test_new_users_get_popular_authors(): void
    {
        $me = $this->member();
        $popular = $this->member();
        $fan = $this->member();

        $post = $this->makePost($popular, 'general', 2);

        PostLike::create(['post_id' => $post->id, 'user_id' => $fan->id]);

        Sanctum::actingAs($me);

        $this->getJson('/api/users/suggestions')
            ->assertOk()
            ->assertJsonPath('users.0.id', $popular->id)
            ->assertJsonPath('users.0.reason', 'โพสต์ได้รับถูกใจมากในชุมชน');
    }
}
