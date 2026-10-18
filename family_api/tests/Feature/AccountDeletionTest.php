<?php

namespace Tests\Feature;

use App\Models\Activity;
use App\Models\Comment;
use App\Models\Post;
use App\Models\User;
use App\Models\UserLocation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class AccountDeletionTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    // =====================================================
    // ลบบัญชีในแอป: ข้อมูลหายครบ และ Token ใช้ไม่ได้อีก
    // =====================================================

    public function test_member_can_delete_account_and_all_data(): void
    {
        Storage::fake(User::profilePhotoDisk());

        $owner = User::factory()->create();
        $member = User::factory()->create([
            'password' => 'secret-pass',
            'profile_photo' => 'profile_photos/member.jpg',
        ]);

        Storage::disk(User::profilePhotoDisk())
            ->put('profile_photos/member.jpg', 'photo');

        $family = $this->createFamily($owner, [$member]);

        $post = Post::create([
            'family_id' => $family->id,
            'user_id' => $member->id,
            'content' => 'Hello',
        ]);

        $ownerPost = Post::create([
            'family_id' => $family->id,
            'user_id' => $owner->id,
            'content' => 'Owner post',
        ]);

        Comment::create([
            'post_id' => $ownerPost->id,
            'user_id' => $member->id,
            'content' => 'Nice',
        ]);

        UserLocation::create([
            'user_id' => $member->id,
            'latitude' => 13.7,
            'longitude' => 100.5,
        ]);

        Activity::create([
            'user_id' => $member->id,
            'visibility' => 'private',
            'title' => 'Gym',
        ]);

        $token = $member->createToken('family-app')->plainTextToken;

        $this->withToken($token)
            ->deleteJson('/api/account', ['password' => 'secret-pass'])
            ->assertOk()
            ->assertJson(['status' => true]);

        $this->assertDatabaseMissing('users', ['id' => $member->id]);
        $this->assertDatabaseMissing('family_members', ['user_id' => $member->id]);
        $this->assertDatabaseMissing('posts', ['id' => $post->id]);
        $this->assertDatabaseMissing('comments', ['user_id' => $member->id]);
        $this->assertDatabaseMissing('user_locations', ['user_id' => $member->id]);
        $this->assertDatabaseMissing('activities', ['user_id' => $member->id]);
        $this->assertDatabaseMissing('personal_access_tokens', [
            'tokenable_id' => $member->id,
        ]);

        Storage::disk(User::profilePhotoDisk())
            ->assertMissing('profile_photos/member.jpg');

        // ครอบครัวและโพสต์ของคนอื่นยังอยู่
        $this->assertDatabaseHas('families', ['id' => $family->id]);
        $this->assertDatabaseHas('posts', ['id' => $ownerPost->id]);

        // Token เดิมใช้ไม่ได้แล้ว
        $this->app['auth']->forgetGuards();

        $this->withToken($token)
            ->getJson('/api/user')
            ->assertUnauthorized();
    }

    // =====================================================
    // รหัสผ่านผิด → ไม่ลบ
    // =====================================================

    public function test_wrong_password_does_not_delete_account(): void
    {
        $user = User::factory()->create(['password' => 'secret-pass']);

        $this->createFamily($user);

        $this->actingAs($user)
            ->deleteJson('/api/account', ['password' => 'wrong-pass'])
            ->assertStatus(422);

        $this->assertDatabaseHas('users', ['id' => $user->id]);
    }

    // =====================================================
    // Owner ที่ยังมีสมาชิก → ต้องโอนสิทธิ์ก่อน
    // =====================================================

    public function test_owner_with_members_must_transfer_ownership_first(): void
    {
        $owner = User::factory()->create(['password' => 'secret-pass']);
        $member = User::factory()->create();

        $family = $this->createFamily($owner, [$member]);

        $this->actingAs($owner)
            ->deleteJson('/api/account', ['password' => 'secret-pass'])
            ->assertStatus(409)
            ->assertJsonPath('code', 'transfer_owner_required');

        $this->assertDatabaseHas('users', ['id' => $owner->id]);
        $this->assertDatabaseHas('families', ['id' => $family->id]);
        $this->assertDatabaseHas('family_members', ['user_id' => $member->id]);
    }

    // =====================================================
    // Owner คนเดียวในครอบครัว → ลบครอบครัวไปด้วย
    // =====================================================

    public function test_sole_owner_deletes_family_too(): void
    {
        $owner = User::factory()->create(['password' => 'secret-pass']);

        $family = $this->createFamily($owner);

        $this->actingAs($owner)
            ->deleteJson('/api/account', ['password' => 'secret-pass'])
            ->assertOk();

        $this->assertDatabaseMissing('users', ['id' => $owner->id]);
        $this->assertDatabaseMissing('families', ['id' => $family->id]);
    }

    // =====================================================
    // หน้าเว็บ /account/delete
    // =====================================================

    public function test_web_form_deletes_account(): void
    {
        $user = User::factory()->create([
            'email' => 'delete-me@example.com',
            'password' => 'secret-pass',
        ]);

        $this->get('/account/delete')
            ->assertOk()
            ->assertSee('ลบบัญชีถาวร');

        $this->post('/account/delete', [
            'email' => 'delete-me@example.com',
            'password' => 'secret-pass',
            'confirm' => '1',
        ])
            ->assertOk()
            ->assertSee('ลบบัญชีเรียบร้อยแล้ว');

        $this->assertDatabaseMissing('users', ['id' => $user->id]);
    }

    public function test_web_form_rejects_wrong_password_or_missing_confirm(): void
    {
        $user = User::factory()->create([
            'email' => 'keep-me@example.com',
            'password' => 'secret-pass',
        ]);

        $this->from('/account/delete')
            ->post('/account/delete', [
                'email' => 'keep-me@example.com',
                'password' => 'wrong-pass',
                'confirm' => '1',
            ])
            ->assertRedirect('/account/delete')
            ->assertSessionHasErrors('email');

        $this->from('/account/delete')
            ->post('/account/delete', [
                'email' => 'keep-me@example.com',
                'password' => 'secret-pass',
            ])
            ->assertRedirect('/account/delete')
            ->assertSessionHasErrors('confirm');

        $this->assertDatabaseHas('users', ['id' => $user->id]);
    }
}
