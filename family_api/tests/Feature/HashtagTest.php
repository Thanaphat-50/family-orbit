<?php

namespace Tests\Feature;

use App\Models\FamilyMember;
use App\Models\Hashtag;
use App\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class HashtagTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function member(): User
    {
        $user = User::factory()->create(['community_terms_accepted_at' => now()]);

        $this->createFamily($user);

        return $user;
    }

    private function makePost(User $author, string $content, string $visibility = 'community'): Post
    {
        return Post::create([
            'family_id' => FamilyMember::where('user_id', $author->id)->value('family_id'),
            'user_id' => $author->id,
            'visibility' => $visibility,
            'category' => $visibility === 'community' ? 'general' : null,
            'content' => $content,
        ]);
    }

    public function test_extracts_thai_and_english_hashtags(): void
    {
        $this->assertSame(
            ['ทำอาหาร', 'อร่อยมาก', 'cooking', 'แกง_เขียวหวาน'],
            Hashtag::extract("วันนี้ #ทำอาหาร #อร่อยมาก\n#Cooking #cooking #1 #แกง_เขียวหวาน")
        );

        // # กลางคำ / ในลิงก์ ไม่ใช่แท็ก
        $this->assertSame([], Hashtag::extract('ดูที่ example.com/#top หรือ abc#def'));

        $this->assertSame([], Hashtag::extract('#' . str_repeat('ก', 51)));

        $many = implode(' ', array_map(fn ($i) => "#tag{$i}", range(1, 15)));

        $this->assertCount(Hashtag::MAX_PER_POST, Hashtag::extract($many));
    }

    public function test_posting_saves_hashtags_and_feed_filters_by_tag(): void
    {
        $me = $this->member();
        $other = $this->member();

        Sanctum::actingAs($me);

        $postId = $this->postJson('/api/posts', [
            'content' => 'แกงเขียวหวานสูตรยาย #ทำอาหาร #Thai',
            'visibility' => 'community',
        ])->assertCreated()->json('post.id');

        $this->assertEqualsCanonicalizing(
            ['ทำอาหาร', 'thai'],
            Post::find($postId)->hashtags()->pluck('name')->all()
        );

        $this->makePost($other, 'ข้าวผัด #ทำอาหาร');
        $this->makePost($other, 'ไม่มีแท็ก');
        // โพสต์ครอบครัวไม่ขึ้นในหน้าแฮชแท็กของชุมชน
        $this->makePost($other, 'กลุ่ม #ทำอาหาร', 'family');
        // ถูกซ่อน
        $hidden = $this->makePost($other, 'ซ่อน #ทำอาหาร');
        $hidden->hidden_at = now();
        $hidden->save();

        $this->getJson('/api/posts?scope=community&hashtag=ทำอาหาร')
            ->assertOk()
            ->assertJsonPath('hashtag', 'ทำอาหาร')
            ->assertJsonCount(2, 'posts');

        // ส่งมาพร้อม # และตัวพิมพ์ใหญ่ก็ได้
        $this->getJson('/api/posts?scope=community&hashtag=' . urlencode('#THAI'))
            ->assertJsonCount(1, 'posts')
            ->assertJsonPath('posts.0.id', $postId);

        // แท็กของโพสต์ตามการแก้ข้อความ
        $post = Post::find($postId);
        $post->content = 'เปลี่ยนแล้ว #ขนม';
        $post->save();

        $this->assertSame(['ขนม'], $post->hashtags()->pluck('name')->all());
    }

    public function test_popular_hashtags_count_visible_community_posts(): void
    {
        $author = $this->member();

        $this->makePost($author, '#ทำอาหาร #ต้นไม้');
        $this->makePost($author, '#ทำอาหาร');
        $this->makePost($author, '#ทำอาหาร #ต้นไม้ #แมว');
        $this->makePost($author, '#ลับเฉพาะกลุ่ม', 'family');

        $old = $this->makePost($author, '#เก่ามาก');
        $old->created_at = now()->subDays(40);
        $old->save();

        Sanctum::actingAs($this->member());

        $this->getJson('/api/hashtags/popular')
            ->assertOk()
            ->assertJsonCount(3, 'hashtags')
            ->assertJsonPath('hashtags.0.name', 'ทำอาหาร')
            ->assertJsonPath('hashtags.0.posts_count', 3)
            ->assertJsonPath('hashtags.1.name', 'ต้นไม้')
            ->assertJsonPath('hashtags.2.name', 'แมว');
    }
}
