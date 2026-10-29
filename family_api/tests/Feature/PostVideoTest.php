<?php

namespace Tests\Feature;

use App\Models\Post;
use App\Models\PostVideo;
use App\Models\User;
use App\Services\AccountDeletionService;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class PostVideoTest extends TestCase
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

    private function video(int $kb = 2000): UploadedFile
    {
        return UploadedFile::fake()->create('clip.mp4', $kb, 'video/mp4');
    }

    public function test_post_with_a_video_file_and_thumbnail(): void
    {
        $me = $this->member();

        Sanctum::actingAs($me);

        $this->post('/api/posts', [
            'visibility' => 'community',
            'video' => $this->video(),
            'video_thumbnail' => UploadedFile::fake()->create('thumb.jpg', 40, 'image/jpeg'),
            'video_duration' => 12,
            'video_width' => 720,
            'video_height' => 1280,
        ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('post.video.duration_seconds', 12)
            ->assertJsonPath('post.video.height', 1280);

        $video = PostVideo::first();

        Storage::disk(MediaStorage::disk())->assertExists($video->path);
        Storage::disk(MediaStorage::disk())->assertExists($video->thumbnail_path);
        $this->assertStringStartsWith('post_videos/' . $me->id . '/', $video->path);

        $this->getJson('/api/posts?scope=community')
            ->assertOk()
            ->assertJsonPath('posts.0.video.duration_seconds', 12)
            ->assertJsonStructure(['posts' => [['video' => ['url', 'thumbnail_url']]]])
            ->assertJsonMissingPath('posts.0.video.path');
    }

    public function test_video_already_uploaded_to_the_bucket(): void
    {
        $me = $this->member();
        $other = $this->member();

        $disk = Storage::disk(MediaStorage::disk());

        $disk->put("post_videos/{$me->id}/abc-123.mp4", str_repeat('v', 2048));
        $disk->put("post_videos/{$other->id}/someone-else.mp4", 'x');

        Sanctum::actingAs($me);

        $this->postJson('/api/posts', ['video_path' => "post_videos/{$me->id}/abc-123.mp4"])
            ->assertCreated()
            ->assertJsonPath('post.video.duration_seconds', null);

        $this->assertSame(2048, PostVideo::first()->size_bytes);

        // ของคนอื่น / ไม่มีไฟล์ / นอกโฟลเดอร์ → ไม่รับ
        $this->postJson('/api/posts', ['video_path' => "post_videos/{$other->id}/someone-else.mp4"])
            ->assertStatus(422);
        $this->postJson('/api/posts', ['video_path' => "post_videos/{$me->id}/missing.mp4"])
            ->assertStatus(422);
        $this->postJson('/api/posts', ['video_path' => '../.env'])
            ->assertStatus(422);

        $this->assertSame(1, PostVideo::count());
    }

    public function test_upload_url_depends_on_the_storage(): void
    {
        $me = $this->member();

        Sanctum::actingAs($me);

        // ที่เก็บในเครื่อง → แอปส่งไฟล์มากับโพสต์
        $this->postJson('/api/posts/video-upload')
            ->assertOk()
            ->assertJsonPath('upload', null)
            ->assertJsonPath('max_seconds', PostVideo::MAX_SECONDS);

        // Bucket บน Cloud → ได้ลิงก์ PUT ตรง
        config(['filesystems.default' => 's3']);

        Storage::fake('s3');

        Storage::disk('s3')->buildTemporaryUploadUrlsUsing(
            fn ($path, $expiration) => [
                'url' => 'https://bucket.test/' . $path . '?signature=abc',
                'headers' => ['Host' => ['bucket.test']],
            ]
        );

        $upload = $this->postJson('/api/posts/video-upload')
            ->assertOk()
            ->assertJsonPath('upload.headers.Content-Type', 'video/mp4')
            ->assertJsonMissingPath('upload.headers.Host')
            ->json('upload');

        $this->assertMatchesRegularExpression('#^post_videos/' . $me->id . '/[A-Za-z0-9-]+\.mp4$#', $upload['path']);
        $this->assertStringContainsString($upload['path'], $upload['url']);
    }

    public function test_rules_for_videos(): void
    {
        $me = $this->member();

        Sanctum::actingAs($me);

        // รูปกับวิดีโอพร้อมกันไม่ได้
        $this->post('/api/posts', [
            'video' => $this->video(),
            'images' => [UploadedFile::fake()->create('a.jpg', 40, 'image/jpeg')],
        ], ['Accept' => 'application/json'])->assertStatus(422);

        // ใหญ่เกิน 50 MB
        $this->post('/api/posts', ['video' => $this->video(PostVideo::MAX_KB + 1)], ['Accept' => 'application/json'])
            ->assertStatus(422);

        // ยาวเกิน
        $this->post('/api/posts', [
            'video' => $this->video(),
            'video_duration' => PostVideo::MAX_SECONDS + 30,
        ], ['Accept' => 'application/json'])->assertStatus(422);

        // ไม่ใช่วิดีโอ
        $this->post('/api/posts', [
            'video' => UploadedFile::fake()->create('notes.pdf', 10, 'application/pdf'),
        ], ['Accept' => 'application/json'])->assertStatus(422);

        $this->assertSame(0, Post::count());
    }

    public function test_deleting_the_post_or_account_removes_video_files(): void
    {
        $me = $this->member();

        Sanctum::actingAs($me);

        $postId = $this->post('/api/posts', [
            'video' => $this->video(),
            'video_thumbnail' => UploadedFile::fake()->create('thumb.jpg', 40, 'image/jpeg'),
        ], ['Accept' => 'application/json'])->assertCreated()->json('post.id');

        $paths = PostVideo::first()->filePaths();

        $this->deleteJson("/api/posts/{$postId}")->assertOk();

        foreach ($paths as $path) {
            Storage::disk(MediaStorage::disk())->assertMissing($path);
        }

        $this->post('/api/posts', ['video' => $this->video()], ['Accept' => 'application/json'])
            ->assertCreated();

        $path = PostVideo::first()->path;

        app(AccountDeletionService::class)->delete($me->fresh());

        Storage::disk(MediaStorage::disk())->assertMissing($path);
    }

    public function test_reposts_carry_the_original_video(): void
    {
        $author = $this->member();
        $sharer = $this->member();

        Sanctum::actingAs($author);

        $postId = $this->post('/api/posts', [
            'visibility' => 'community',
            'video' => $this->video(),
            'video_duration' => 8,
        ], ['Accept' => 'application/json'])->json('post.id');

        Sanctum::actingAs($sharer);

        $this->postJson("/api/posts/{$postId}/share", ['channel' => 'community'])
            ->assertCreated()
            ->assertJsonPath('post.shared_post.video.duration_seconds', 8);
    }
}
