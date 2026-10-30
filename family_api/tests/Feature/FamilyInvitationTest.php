<?php

namespace Tests\Feature;

use App\Models\FamilyInvitation;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class FamilyInvitationTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private function familyId(User $user): ?int
    {
        return FamilyMember::where('user_id', $user->id)->value('family_id');
    }

    // =====================================================
    // ชวนเข้าครอบครัว
    // =====================================================

    public function test_member_invites_by_email_and_invitee_accepts(): void
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();
        $family = $this->createFamily($mom, [$dad]);

        $grandma = User::factory()->create(['email' => 'grandma@example.com']);

        // สมาชิกธรรมดาชวนได้
        Sanctum::actingAs($dad);

        $this->postJson('/api/family-invitations', ['email' => 'GRANDMA@example.com '])
            ->assertOk()
            ->assertJsonPath('invitation.type', 'invite')
            ->assertJsonPath('invitation.family.id', $family->id);

        // ชวนซ้ำไม่สร้างใหม่
        $this->postJson('/api/family-invitations', ['user_id' => $grandma->id])->assertOk();

        $this->assertSame(1, FamilyInvitation::count());

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $grandma->id,
            'type' => 'family_invite',
        ]);

        $this->getJson('/api/family-invitations')
            ->assertJsonCount(1, 'invited')
            ->assertJsonCount(0, 'requests');

        Sanctum::actingAs($grandma);

        $invitationId = $this->getJson('/api/family-invitations')
            ->assertOk()
            ->assertJsonPath('has_family', false)
            ->assertJsonCount(1, 'received')
            ->assertJsonPath('received.0.family.members_count', 2)
            ->assertJsonPath('received.0.creator.id', $dad->id)
            ->json('received.0.id');

        $this->postJson("/api/family-invitations/{$invitationId}/accept")
            ->assertOk()
            ->assertJsonPath('joined', true);

        $this->assertSame($family->id, $this->familyId($grandma));

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $mom->id,
            'type' => 'member_joined',
        ]);

        // ใช้แล้วกดซ้ำไม่ได้
        $this->postJson("/api/family-invitations/{$invitationId}/accept")->assertNotFound();
    }

    public function test_invite_rules(): void
    {
        $mom = User::factory()->create();
        $this->createFamily($mom);

        $other = User::factory()->create();
        $this->createFamily($other);

        $blocked = User::factory()->create();
        $blocked->blockedUsers()->attach($mom->id);

        $loner = User::factory()->create();

        Sanctum::actingAs($mom);

        $this->postJson('/api/family-invitations', ['email' => 'nobody@example.com'])->assertNotFound();
        $this->postJson('/api/family-invitations', ['user_id' => $mom->id])->assertStatus(422);
        $this->postJson('/api/family-invitations', ['user_id' => $other->id])->assertStatus(409);
        $this->postJson('/api/family-invitations', ['user_id' => $blocked->id])->assertForbidden();
        $this->postJson('/api/family-invitations', [])->assertStatus(422);

        // ยังไม่มีครอบครัว → ชวนใครไม่ได้
        Sanctum::actingAs($loner);

        $this->postJson('/api/family-invitations', ['user_id' => $blocked->id])->assertForbidden();
    }

    public function test_invitee_can_decline_and_inviter_can_cancel(): void
    {
        $mom = User::factory()->create();
        $this->createFamily($mom);

        $aunt = User::factory()->create();
        $uncle = User::factory()->create();

        Sanctum::actingAs($mom);

        $toAunt = $this->postJson('/api/family-invitations', ['user_id' => $aunt->id])->json('invitation.id');
        $toUncle = $this->postJson('/api/family-invitations', ['user_id' => $uncle->id])->json('invitation.id');

        $this->deleteJson("/api/family-invitations/{$toUncle}")->assertOk();

        Sanctum::actingAs($aunt);

        $this->postJson("/api/family-invitations/{$toAunt}/decline")->assertOk();

        $this->assertNull($this->familyId($aunt));
        $this->assertSame(FamilyInvitation::DECLINED, FamilyInvitation::find($toAunt)->status);
        $this->assertSame(FamilyInvitation::CANCELED, FamilyInvitation::find($toUncle)->status);

        // คนอื่นตอบแทนไม่ได้
        Sanctum::actingAs($uncle);

        $this->postJson("/api/family-invitations/{$toAunt}/accept")->assertNotFound();
    }

    // =====================================================
    // ขอเข้าครอบครัว
    // =====================================================

    public function test_request_to_join_then_owner_approves(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create();
        $family = $this->createFamily($owner, [$member]);

        $cousin = User::factory()->create();

        // คนที่ยังไม่มีครอบครัวเห็นปุ่ม "ขอเข้าครอบครัว" ในโปรไฟล์
        Post::create([
            'family_id' => $family->id,
            'user_id' => $member->id,
            'visibility' => 'community',
            'content' => 'สวัสดี',
        ]);

        Sanctum::actingAs($cousin);

        $this->getJson("/api/users/{$member->id}/profile")
            ->assertOk()
            ->assertJsonPath('profile.can_request_join', true)
            ->assertJsonPath('profile.can_invite', false);

        $this->postJson("/api/users/{$member->id}/family-request")
            ->assertOk()
            ->assertJsonPath('invitation.type', 'request');

        $this->getJson("/api/users/{$member->id}/profile")
            ->assertJsonPath('profile.pending_invitation.type', 'request');

        $this->getJson('/api/family-invitations')->assertJsonCount(1, 'sent');

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $owner->id,
            'type' => 'family_request',
        ]);

        $requestId = FamilyInvitation::first()->id;

        // สมาชิกธรรมดาอนุมัติไม่ได้ / ไม่เห็นคำขอ
        Sanctum::actingAs($member);

        $this->getJson('/api/family-invitations')->assertJsonCount(0, 'requests');
        $this->postJson("/api/family-invitations/{$requestId}/accept")->assertNotFound();

        Sanctum::actingAs($owner);

        $this->getJson('/api/family-invitations')
            ->assertJsonPath('is_owner', true)
            ->assertJsonCount(1, 'requests')
            ->assertJsonPath('requests.0.user.id', $cousin->id);

        $this->postJson("/api/family-invitations/{$requestId}/accept")->assertOk();

        $this->assertSame($family->id, $this->familyId($cousin));

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $cousin->id,
            'type' => 'family_request_accepted',
        ]);
    }

    public function test_matching_invite_and_request_join_right_away(): void
    {
        $owner = User::factory()->create();
        $family = $this->createFamily($owner);

        $friend = User::factory()->create();

        // ขอเข้าไว้ก่อน → Owner กดชวน = รับเข้าเลย
        Sanctum::actingAs($friend);
        $this->postJson("/api/users/{$owner->id}/family-request")->assertOk();

        Sanctum::actingAs($owner);
        $this->postJson('/api/family-invitations', ['user_id' => $friend->id])
            ->assertOk()
            ->assertJsonPath('joined', true);

        $this->assertSame($family->id, $this->familyId($friend));

        // ชวนไว้ก่อน → อีกฝ่ายกดขอเข้า = รับคำเชิญเลย
        $buddy = User::factory()->create();

        $this->postJson('/api/family-invitations', ['user_id' => $buddy->id])->assertOk();

        Sanctum::actingAs($buddy);
        $this->postJson("/api/users/{$owner->id}/family-request")
            ->assertOk()
            ->assertJsonPath('joined', true);

        $this->assertSame($family->id, $this->familyId($buddy));
    }

    public function test_joining_any_family_closes_other_pending_invitations(): void
    {
        $a = User::factory()->create();
        $familyA = $this->createFamily($a);

        $b = User::factory()->create();
        $this->createFamily($b);

        $newcomer = User::factory()->create();

        Sanctum::actingAs($a);
        $fromA = $this->postJson('/api/family-invitations', ['user_id' => $newcomer->id])->json('invitation.id');

        Sanctum::actingAs($b);
        $fromB = $this->postJson('/api/family-invitations', ['user_id' => $newcomer->id])->json('invitation.id');

        Sanctum::actingAs($newcomer);

        // เข้าด้วยรหัสเชิญของ A แทน
        $this->postJson('/api/families/join', ['invite_code' => $familyA->invite_code])->assertOk();

        $this->assertSame(FamilyInvitation::CANCELED, FamilyInvitation::find($fromA)->status);
        $this->assertSame(FamilyInvitation::CANCELED, FamilyInvitation::find($fromB)->status);

        $this->getJson('/api/family-invitations')->assertJsonCount(0, 'received');

        $this->postJson("/api/family-invitations/{$fromB}/accept")->assertNotFound();
    }

    public function test_cannot_request_when_already_in_a_family_or_target_has_none(): void
    {
        $mom = User::factory()->create();
        $this->createFamily($mom);

        $loner = User::factory()->create();
        $another = User::factory()->create();

        Sanctum::actingAs($mom);
        $this->postJson("/api/users/{$loner->id}/family-request")->assertStatus(409);

        Sanctum::actingAs($loner);
        $this->postJson("/api/users/{$another->id}/family-request")->assertNotFound();
    }
}
