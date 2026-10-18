<?php

namespace Tests\Feature;

use App\Filament\Resources\Posts\Pages\ListPosts;
use App\Filament\Widgets\AppStatsOverview;
use App\Models\Post;
use App\Models\PostReport;
use App\Models\User;
use Filament\Actions\Testing\TestAction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class AdminPanelTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function admin(): User
    {
        $admin = User::factory()->create();
        $admin->is_admin = true;
        $admin->save();

        return $admin;
    }

    // =====================================================
    // สิทธิ์เข้าหน้า Admin
    // =====================================================

    public function test_guest_is_redirected_to_admin_login(): void
    {
        $this->get('/admin')->assertRedirect('/admin/login');
    }

    public function test_regular_user_cannot_open_admin_panel(): void
    {
        $user = User::factory()->create();

        $this->actingAs($user)->get('/admin')->assertForbidden();
    }

    public function test_admin_can_open_dashboard_and_users(): void
    {
        $this->actingAs($this->admin());

        $this->get('/admin')->assertOk();
        $this->get('/admin/users')->assertOk();

        // Widget บน Dashboard โหลดแบบ lazy จึงทดสอบตัว Widget โดยตรง
        Livewire::test(AppStatsOverview::class)
            ->assertSee('ผู้ใช้ทั้งหมด')
            ->assertSee('รายงานรอตรวจ');
    }

    // =====================================================
    // หน้าโพสต์ชุมชน: แสดงเฉพาะโพสต์ชุมชน
    // (โพสต์ครอบครัวเป็นข้อมูลส่วนตัว)
    // =====================================================

    public function test_admin_sees_only_community_posts(): void
    {
        $author = User::factory()->create();
        $family = $this->createFamily($author);

        Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'content' => 'Public hello',
        ]);

        Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'content' => 'Private family note',
        ]);

        $this->actingAs($this->admin())
            ->get('/admin/posts')
            ->assertOk()
            ->assertSee('Public hello')
            ->assertDontSee('Private family note');
    }

    // =====================================================
    // ซ่อน / คืนโพสต์
    // =====================================================

    public function test_admin_can_hide_and_restore_post(): void
    {
        $author = User::factory()->create();
        $reporter = User::factory()->create();
        $family = $this->createFamily($author);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'content' => 'Reported post',
        ]);

        PostReport::create([
            'post_id' => $post->id,
            'user_id' => $reporter->id,
            'reason' => 'spam',
        ]);

        $this->actingAs($this->admin());

        Livewire::test(ListPosts::class)
            ->callAction(TestAction::make('hide')->table($post));

        $this->assertNotNull($post->fresh()->hidden_at);

        Livewire::test(ListPosts::class)
            ->callAction(TestAction::make('restore')->table($post));

        $this->assertNull($post->fresh()->hidden_at);
        $this->assertSame(0, $post->reports()->count());
    }

    // =====================================================
    // คำสั่ง app:make-admin
    // =====================================================

    public function test_make_admin_command_grants_and_revokes(): void
    {
        $user = User::factory()->create(['email' => 'boss@example.com']);

        $this->artisan('app:make-admin', ['email' => 'boss@example.com'])
            ->assertSuccessful();

        $this->assertTrue($user->fresh()->is_admin);

        $this->artisan('app:make-admin', [
            'email' => 'boss@example.com',
            '--revoke' => true,
        ])->assertSuccessful();

        $this->assertFalse($user->fresh()->is_admin);

        $this->artisan('app:make-admin', ['email' => 'nobody@example.com'])
            ->assertFailed();
    }

    // =====================================================
    // API ไม่ส่ง is_admin ออกไป
    // =====================================================

    public function test_api_does_not_expose_is_admin(): void
    {
        $this->actingAs($this->admin())
            ->getJson('/api/user')
            ->assertOk()
            ->assertJsonMissingPath('is_admin');
    }
}
