<?php

namespace Tests\Feature;

use App\Models\Comment;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\PostVideo;
use App\Models\User;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class CommentMediaTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());
    }

    private function member(): User
    {
        $user = User::factory()->create(['community_terms_accepted_at' => now()]);

        $this->createFamily($user);

        return $user;
    }

    private function communityPost(User $author): Post
    {
        return Post::create([
            'family_id' => FamilyMember::where('user_id', $author->id)->value('family_id'),
            'user_id' => $author->id,
            'visibility' => 'community',
            'category' => 'general',
            'content' => 'คลิปผีเสื้อ',
        ]);
    }

    private function storage()
    {
        return Storage::disk(MediaStorage::disk());
    }

    public function test_comment_with_image_gif_or_video(): void
    {
        $author = $this->member();
        $post = $this->communityPost($author);

        Sanctum::actingAs($this->member());

        // รูป + ข้อความ
        $this->post("/api/posts/{$post->id}/comments", [
            'content' => 'สวยมาก',
            'media' => UploadedFile::fake()->create('photo.jpg', 300, 'image/jpeg'),
            'media_width' => 800,
            'media_height' => 600,
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('comment.media.type', 'image')
            ->assertJsonPath('comment.media.width', 800)
            ->assertJsonMissingPath('comment.media_path');

        // GIF อย่างเดียว ไม่มีข้อความ
        $this->post("/api/posts/{$post->id}/comments", [
            'media' => UploadedFile::fake()->create('funny.gif', 500, 'image/gif'),
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('comment.content', null)
            ->assertJsonPath('comment.media.type', 'gif');

        // วิดีโอ + รูปตัวอย่าง
        $video = $this->post("/api/posts/{$post->id}/comments", [
            'media' => UploadedFile::fake()->create('clip.mp4', 3000, 'video/mp4'),
            'media_thumbnail' => UploadedFile::fake()->create('thumb.jpg', 40, 'image/jpeg'),
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('comment.media.type', 'video')
            ->json('comment');

        $this->assertNotNull($video['media']['url']);
        $this->assertNotNull($video['media']['thumbnail_url']);

        $saved = Comment::find($video['id']);

        $this->storage()->assertExists($saved->media_path);
        $this->storage()->assertExists($saved->media_thumbnail_path);

        // ในฟีดเห็นไฟล์แนบของความคิดเห็น
        $this->getJson('/api/posts?scope=community&sort=latest')
            ->assertJsonPath('posts.0.comments.1.media.type', 'gif');

        // ประวัติการใช้งานมีข้อความแทนไฟล์
        $this->getJson('/api/me/history?type=comment')
            ->assertJsonPath('items.0.excerpt', 'ส่งวิดีโอ')
            ->assertJsonPath('items.1.excerpt', 'ส่ง GIF');
    }

    public function test_comment_media_rules(): void
    {
        $post = $this->communityPost($this->member());

        Sanctum::actingAs($this->member());

        $url = "/api/posts/{$post->id}/comments";

        $this->postJson($url, [])->assertStatus(422)->assertJsonValidationErrors('content');

        $this->post($url, [
            'media' => UploadedFile::fake()->create('doc.pdf', 100, 'application/pdf'),
        ], ['Accept' => 'application/json'])->assertStatus(422)->assertJsonValidationErrors('media');

        // รูปเกิน 10 MB (วิดีโอได้ถึง 20 MB)
        $this->post($url, [
            'media' => UploadedFile::fake()->create('big.jpg', 11000, 'image/jpeg'),
        ], ['Accept' => 'application/json'])->assertStatus(422);

        $this->post($url, [
            'media' => UploadedFile::fake()->create('big.mp4', 21000, 'video/mp4'),
        ], ['Accept' => 'application/json'])->assertStatus(422);

        $this->assertSame(0, Comment::count());
        $this->assertSame([], $this->storage()->allFiles());
    }

    public function test_files_are_removed_with_the_comment_post_or_family(): void
    {
        $author = $this->member();
        $post = $this->communityPost($author);

        $fan = $this->member();

        Sanctum::actingAs($fan);

        $commentId = $this->post("/api/posts/{$post->id}/comments", [
            'media' => UploadedFile::fake()->create('a.gif', 50, 'image/gif'),
        ], ['Accept' => 'application/json'])->json('comment.id');

        $first = Comment::find($commentId)->media_path;

        // ลบความคิดเห็นเอง
        $this->deleteJson("/api/comments/{$commentId}")->assertOk();

        $this->storage()->assertMissing($first);

        // ลบโพสต์ → ไฟล์ในความคิดเห็นหายด้วย
        $second = Comment::find($this->post("/api/posts/{$post->id}/comments", [
            'media' => UploadedFile::fake()->create('b.jpg', 50, 'image/jpeg'),
        ], ['Accept' => 'application/json'])->json('comment.id'))->media_path;

        Sanctum::actingAs($author);

        $this->deleteJson("/api/posts/{$post->id}")->assertOk();

        $this->storage()->assertMissing($second);

        // ลบครอบครัว → วิดีโอของโพสต์และไฟล์ในความคิดเห็นหายด้วย
        $familyPost = $this->communityPost($author);

        $this->storage()->put('post_videos/clip.mp4', 'v');

        PostVideo::create(['post_id' => $familyPost->id, 'path' => 'post_videos/clip.mp4']);

        Sanctum::actingAs($fan);

        $third = Comment::find($this->post("/api/posts/{$familyPost->id}/comments", [
            'media' => UploadedFile::fake()->create('c.jpg', 50, 'image/jpeg'),
        ], ['Accept' => 'application/json'])->json('comment.id'))->media_path;

        Sanctum::actingAs($author);

        $this->deleteJson('/api/families/current')->assertOk();

        $this->storage()->assertMissing($third);
        $this->storage()->assertMissing('post_videos/clip.mp4');
    }
}
