<?php

namespace Tests\Feature;

use App\Filament\Resources\Comments\Pages\ListComments;
use App\Models\Comment;
use App\Models\CommentReport;
use App\Models\Family;
use App\Models\Post;
use App\Models\User;
use Filament\Actions\Testing\TestAction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class CommentReportTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function communityPostWithComment(
        User $postAuthor,
        Family $family,
        User $commenter
    ): Comment {
        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $postAuthor->id,
            'visibility' => 'community',
            'content' => 'Community post',
        ]);

        return Comment::create([
            'post_id' => $post->id,
            'user_id' => $commenter->id,
            'content' => 'Rude comment',
        ]);
    }

    private function commentContents($response): array
    {
        return collect($response->json('posts'))
            ->flatMap(fn ($post) => collect($post['comments'])->pluck('content'))
            ->all();
    }

    // =====================================================
    // รายงานครบ 3 คน → ซ่อนอัตโนมัติ
    // คนที่รายงานแล้วไม่เห็นความคิดเห็นนั้นอีก
    // =====================================================

    public function test_comment_is_hidden_after_three_reports(): void
    {
        $author = User::factory()->create();
        $troll = User::factory()->create();
        $family = $this->createFamily($author);
        $this->createFamily($troll);

        $comment = $this->communityPostWithComment($author, $family, $troll);

        $reporters = User::factory()->count(3)->create();

        foreach ($reporters as $index => $reporter) {
            $this->createFamily($reporter);

            Sanctum::actingAs($reporter);

            $this->postJson('/api/comments/' . $comment->id . '/report', [
                'reason' => 'harassment',
            ])->assertOk();

            if ($index === 0) {
                // คนที่รายงานแล้วไม่เห็นความคิดเห็นนั้นในฟีด
                $feed = $this->getJson('/api/posts?scope=community')->assertOk();

                $this->assertNotContains('Rude comment', $this->commentContents($feed));
                $this->assertNull($comment->fresh()->hidden_at);

                // รายงานซ้ำไม่นับเพิ่ม
                $this->postJson('/api/comments/' . $comment->id . '/report', [
                    'reason' => 'spam',
                ])->assertOk();

                $this->assertSame(1, CommentReport::count());
            }
        }

        $this->assertNotNull($comment->fresh()->hidden_at);

        // เจ้าของโพสต์ (ไม่ได้รายงาน) ก็ไม่เห็นแล้วเพราะถูกซ่อน
        Sanctum::actingAs($author);

        $feed = $this->getJson('/api/posts?scope=community')->assertOk();

        $this->assertNotContains('Rude comment', $this->commentContents($feed));
    }

    // =====================================================
    // รายงานความคิดเห็นของตัวเองไม่ได้
    // =====================================================

    public function test_cannot_report_own_comment(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);

        $comment = $this->communityPostWithComment($author, $family, $author);

        Sanctum::actingAs($author);

        $this->postJson('/api/comments/' . $comment->id . '/report', [
            'reason' => 'spam',
        ])->assertStatus(422);

        $this->assertSame(0, CommentReport::count());
    }

    // =====================================================
    // ความคิดเห็นในโพสต์ครอบครัวรายงานไม่ได้
    // =====================================================

    public function test_cannot_report_family_post_comment(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();
        $family = $this->createFamily($mom, [$dad]);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $mom->id,
            'content' => 'Family post',
        ]);

        $comment = Comment::create([
            'post_id' => $post->id,
            'user_id' => $dad->id,
            'content' => 'Family comment',
        ]);

        Sanctum::actingAs($mom);

        $this->postJson('/api/comments/' . $comment->id . '/report', [
            'reason' => 'spam',
        ])->assertStatus(422);
    }

    // =====================================================
    // ลบโพสต์ → รายงานความคิดเห็นถูกลบตาม (ไม่ค้างในฐานข้อมูล)
    // =====================================================

    public function test_reports_are_removed_when_post_is_deleted(): void
    {
        $author = User::factory()->create();
        $troll = User::factory()->create();
        $reporter = User::factory()->create();
        $family = $this->createFamily($author);

        $comment = $this->communityPostWithComment($author, $family, $troll);

        CommentReport::create([
            'comment_id' => $comment->id,
            'user_id' => $reporter->id,
            'reason' => 'spam',
        ]);

        $comment->post->delete();

        $this->assertSame(0, CommentReport::count());
    }

    // =====================================================
    // Admin คืนความคิดเห็น → แสดงอีกครั้งและล้างรายงาน
    // =====================================================

    public function test_admin_can_restore_hidden_comment(): void
    {
        $author = User::factory()->create();
        $troll = User::factory()->create();
        $reporter = User::factory()->create();
        $family = $this->createFamily($author);

        $comment = $this->communityPostWithComment($author, $family, $troll);

        CommentReport::create([
            'comment_id' => $comment->id,
            'user_id' => $reporter->id,
            'reason' => 'spam',
        ]);

        $comment->hidden_at = now();
        $comment->save();

        $admin = User::factory()->create();
        $admin->is_admin = true;
        $admin->save();

        $this->actingAs($admin);

        $this->get('/admin/comments')
            ->assertOk()
            ->assertSee('Rude comment');

        Livewire::test(ListComments::class)
            ->callAction(TestAction::make('restore')->table($comment));

        $this->assertNull($comment->fresh()->hidden_at);
        $this->assertSame(0, $comment->reports()->count());
    }
}
