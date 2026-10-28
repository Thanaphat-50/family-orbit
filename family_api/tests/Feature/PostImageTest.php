<?php

namespace Tests\Feature;

use App\Models\Post;
use App\Models\PostImage;
use App\Models\User;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

class PostImageTest extends TestCase
{
    use CreatesFamilies, FakesImages, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());
    }

    private function png(string $name = 'photo.png'): UploadedFile
    {
        return $this->fakePng($name);
    }

    private function storedFiles(): array
    {
        return Storage::disk(MediaStorage::disk())->allFiles('post_images');
    }

    // =====================================================
    // โพสต์พร้อมรูป → ฟีดส่ง url ของรูปมาตามลำดับ
    // =====================================================

    public function test_post_with_images_shows_urls_in_feed(): void
    {
        $user = User::factory()->create();
        $this->createFamily($user);

        Sanctum::actingAs($user);

        $this->postJson('/api/posts', [
            'content' => 'Trip photos',
            'images' => [$this->png('a.png'), $this->png('b.png')],
        ])
            ->assertCreated()
            ->assertJsonCount(2, 'post.images')
            ->assertJsonPath('post.images.0.sort', 0)
            ->assertJsonMissingPath('post.images.0.path');

        $this->assertCount(2, $this->storedFiles());

        $url = $this->getJson('/api/posts')
            ->assertOk()
            ->assertJsonCount(2, 'posts.0.images')
            ->json('posts.0.images.1.url');

        $this->assertStringContainsString('/storage/post_images/', $url);
    }

    public function test_image_only_post_is_allowed(): void
    {
        $user = User::factory()->create();
        $this->createFamily($user);

        Sanctum::actingAs($user);

        $this->postJson('/api/posts', [
            'images' => [$this->png()],
        ])
            ->assertCreated()
            ->assertJsonPath('post.content', '');

        $this->postJson('/api/posts', ['content' => ''])
            ->assertStatus(422)
            ->assertJsonValidationErrors('content');
    }

    // =====================================================
    // เกิน 10 รูป / ไม่ใช่รูป → 422 และไม่มีไฟล์ค้าง
    // =====================================================

    public function test_invalid_images_are_rejected(): void
    {
        $user = User::factory()->create();
        $this->createFamily($user);

        Sanctum::actingAs($user);

        $tooMany = [];

        for ($i = 0; $i < 11; $i++) {
            $tooMany[] = $this->png("p{$i}.png");
        }

        $this->postJson('/api/posts', [
            'content' => 'Too many',
            'images' => $tooMany,
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('images');

        $this->postJson('/api/posts', [
            'content' => 'Not an image',
            'images' => [
                UploadedFile::fake()->create('doc.pdf', 10, 'application/pdf'),
            ],
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('images.0');

        $this->assertSame(0, Post::count());
        $this->assertSame([], $this->storedFiles());
    }

    // =====================================================
    // ลบโพสต์ / ลบบัญชี / ลบครอบครัว → ไฟล์รูปถูกลบด้วย
    // =====================================================

    public function test_deleting_post_removes_image_files(): void
    {
        $user = User::factory()->create();
        $this->createFamily($user);

        Sanctum::actingAs($user);

        $postId = $this->postJson('/api/posts', [
            'images' => [$this->png('a.png'), $this->png('b.png')],
        ])->json('post.id');

        $this->assertCount(2, $this->storedFiles());

        $this->deleteJson('/api/posts/' . $postId)->assertOk();

        $this->assertSame(0, PostImage::count());
        $this->assertSame([], $this->storedFiles());
    }

    public function test_account_deletion_removes_post_image_files(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create(['password' => 'secret-pass']);
        $this->createFamily($owner, [$member]);

        Sanctum::actingAs($owner);

        $this->postJson('/api/posts', [
            'content' => 'Owner photo',
            'images' => [$this->png('owner.png')],
        ])->assertCreated();

        Sanctum::actingAs($member);

        $this->postJson('/api/posts', [
            'content' => 'Member photo',
            'images' => [$this->png('member.png')],
        ])->assertCreated();

        $this->assertCount(2, $this->storedFiles());

        // ผู้ดูแลอนุมัติคำขอลบบัญชี
        app(\App\Services\AccountDeletionService::class)->delete($member->fresh());

        // เหลือเฉพาะรูปของ Owner
        $this->assertSame(1, PostImage::count());
        $this->assertCount(1, $this->storedFiles());
    }

    public function test_family_deletion_removes_post_image_files(): void
    {
        $owner = User::factory()->create();
        $this->createFamily($owner);

        Sanctum::actingAs($owner);

        $this->postJson('/api/posts', [
            'images' => [$this->png()],
        ])->assertCreated();

        $this->deleteJson('/api/families/current')->assertOk();

        $this->assertSame(0, PostImage::count());
        $this->assertSame([], $this->storedFiles());
    }
}
