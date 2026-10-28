<?php

namespace Tests\Feature;

use App\Filament\Resources\AccountDeletionRequests\Pages\ListAccountDeletionRequests;
use App\Models\AccountDeletionRequest;
use App\Models\Activity;
use App\Models\Comment;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\User;
use App\Models\UserLocation;
use App\Services\AccountDeletionService;
use Filament\Actions\Testing\TestAction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class AccountDeletionTest extends TestCase
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
    // ส่งคำขอในแอป → บัญชียังอยู่ → ผู้ดูแลกดลบ → ข้อมูลหายครบ
    // =====================================================

    public function test_request_then_admin_deletes_account_and_all_data(): void
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
            ->postJson('/api/account/deletion-request', [
                'password' => 'secret-pass',
                'reason' => 'ไม่ได้ใช้แล้ว',
            ])
            ->assertOk()
            ->assertJsonPath('request.status', 'pending')
            ->assertJsonPath('request.process_within_days', 30);

        // ยังไม่ถูกลบ ยังใช้แอปได้
        $this->assertDatabaseHas('users', ['id' => $member->id]);

        $this->withToken($token)
            ->getJson('/api/account/deletion-request')
            ->assertOk()
            ->assertJsonPath('request.status', 'pending');

        // ส่งซ้ำไม่สร้างคำขอใหม่
        $this->withToken($token)
            ->postJson('/api/account/deletion-request', ['password' => 'secret-pass'])
            ->assertOk();

        $this->assertSame(1, AccountDeletionRequest::count());

        $request = AccountDeletionRequest::first();

        $this->assertSame('ไม่ได้ใช้แล้ว', $request->reason);
        $this->assertSame($member->email, $request->email);

        // ผู้ดูแลกดลบในหน้า Admin
        $admin = $this->admin();

        $this->actingAs($admin);

        Livewire::test(ListAccountDeletionRequests::class)
            ->assertCanSeeTableRecords([$request])
            ->callAction(TestAction::make('complete')->table($request));

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

        // เก็บคำขอไว้เป็นหลักฐาน
        $request->refresh();

        $this->assertSame(AccountDeletionRequest::STATUS_COMPLETED, $request->status);
        $this->assertNull($request->user_id);
        $this->assertSame($admin->id, $request->processed_by);

        // Token เดิมใช้ไม่ได้แล้ว
        $this->app['auth']->forgetGuards();

        $this->withToken($token)
            ->getJson('/api/user')
            ->assertUnauthorized();
    }

    // แอปเวอร์ชันเก่าเรียก DELETE /api/account → ได้คำขอ ไม่ลบทันที
    public function test_old_app_delete_call_only_sends_a_request(): void
    {
        $user = User::factory()->create(['password' => 'secret-pass']);

        $this->createFamily($user);

        $this->actingAs($user)
            ->deleteJson('/api/account', ['password' => 'secret-pass'])
            ->assertOk()
            ->assertJson(['status' => true]);

        $this->assertDatabaseHas('users', ['id' => $user->id]);
        $this->assertSame(1, AccountDeletionRequest::pending()->count());
    }

    public function test_user_can_cancel_the_request(): void
    {
        $user = User::factory()->create(['password' => 'secret-pass']);

        $this->actingAs($user)
            ->postJson('/api/account/deletion-request', ['password' => 'secret-pass'])
            ->assertOk();

        $this->deleteJson('/api/account/deletion-request')->assertOk();

        $this->getJson('/api/account/deletion-request')
            ->assertOk()
            ->assertJsonPath('request', null);

        $this->assertSame(
            AccountDeletionRequest::STATUS_CANCELED,
            AccountDeletionRequest::first()->status
        );
    }

    // =====================================================
    // รหัสผ่านผิด → ไม่ส่งคำขอ
    // =====================================================

    public function test_wrong_password_does_not_send_a_request(): void
    {
        $user = User::factory()->create(['password' => 'secret-pass']);

        $this->createFamily($user);

        $this->actingAs($user)
            ->postJson('/api/account/deletion-request', ['password' => 'wrong-pass'])
            ->assertStatus(422);

        $this->assertSame(0, AccountDeletionRequest::count());
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
            ->postJson('/api/account/deletion-request', ['password' => 'secret-pass'])
            ->assertStatus(409)
            ->assertJsonPath('code', 'transfer_owner_required');

        $this->assertSame(0, AccountDeletionRequest::count());
        $this->assertDatabaseHas('families', ['id' => $family->id]);
    }

    // ส่งคำขอแล้วค่อยมีสมาชิกเข้าครอบครัว → ผู้ดูแลลบไม่ได้ จนกว่าจะโอนสิทธิ์
    public function test_admin_cannot_delete_an_owner_who_still_has_members(): void
    {
        $owner = User::factory()->create(['password' => 'secret-pass']);

        $family = $this->createFamily($owner);

        $request = AccountDeletionRequest::requestFor($owner, 'app');

        FamilyMember::create([
            'family_id' => $family->id,
            'user_id' => User::factory()->create()->id,
            'role' => 'member',
        ]);

        $this->actingAs($this->admin());

        Livewire::test(ListAccountDeletionRequests::class)
            ->callAction(TestAction::make('complete')->table($request))
            ->assertNotified('ลบไม่ได้');

        $this->assertDatabaseHas('users', ['id' => $owner->id]);
        $this->assertTrue($request->fresh()->isPending());
    }

    public function test_admin_can_reject_with_a_reason_the_user_sees(): void
    {
        $user = User::factory()->create();

        $request = AccountDeletionRequest::requestFor($user, 'app');

        $this->actingAs($this->admin());

        Livewire::test(ListAccountDeletionRequests::class)
            ->callAction(
                TestAction::make('reject')->table($request),
                ['note' => 'กรุณาโอนสิทธิ์ Owner ก่อน']
            )
            ->assertHasNoFormErrors();

        $this->assertSame(AccountDeletionRequest::STATUS_REJECTED, $request->fresh()->status);
        $this->assertDatabaseHas('users', ['id' => $user->id]);

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $user->id,
            'type' => 'account_deletion',
        ]);
    }

    // =====================================================
    // Owner คนเดียวในครอบครัว → ลบครอบครัวไปด้วย
    // =====================================================

    public function test_sole_owner_deletes_family_too(): void
    {
        $owner = User::factory()->create(['password' => 'secret-pass']);

        $family = $this->createFamily($owner);

        $request = AccountDeletionRequest::requestFor($owner, 'app');

        app(AccountDeletionService::class)->completeRequest($request, null);

        $this->assertDatabaseMissing('users', ['id' => $owner->id]);
        $this->assertDatabaseMissing('families', ['id' => $family->id]);
    }

    // =====================================================
    // หน้าเว็บ /account/delete → ส่งคำขอ
    // =====================================================

    public function test_web_form_sends_a_request(): void
    {
        $user = User::factory()->create([
            'email' => 'delete-me@example.com',
            'password' => 'secret-pass',
        ]);

        $this->get('/account/delete')
            ->assertOk()
            ->assertSee('ส่งคำขอลบบัญชี');

        $this->post('/account/delete', [
            'email' => 'delete-me@example.com',
            'password' => 'secret-pass',
            'reason' => 'ย้ายไปใช้แอปอื่น',
            'confirm' => '1',
        ])
            ->assertOk()
            ->assertSee('ส่งคำขอลบบัญชีแล้ว');

        $this->assertDatabaseHas('users', ['id' => $user->id]);

        $request = AccountDeletionRequest::first();

        $this->assertSame('web', $request->source);
        $this->assertSame('ย้ายไปใช้แอปอื่น', $request->reason);
        $this->assertTrue($request->isPending());
    }

    public function test_web_form_rejects_wrong_password_or_missing_confirm(): void
    {
        User::factory()->create([
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

        $this->assertSame(0, AccountDeletionRequest::count());
    }
}
