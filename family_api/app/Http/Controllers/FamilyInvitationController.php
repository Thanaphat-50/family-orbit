<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\Family;
use App\Models\FamilyInvitation;
use App\Models\FamilyMember;
use App\Models\User;
use App\Models\UserBlock;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

// =======================================================
// ชวนเข้าครอบครัว / ขอเข้าครอบครัว
//
// - ชวน:  คนในครอบครัวชวนผู้ใช้ที่ยังไม่มีครอบครัว (จากโปรไฟล์ หรือด้วยอีเมล)
//         → ผู้ถูกชวนกดรับ/ปฏิเสธ
// - ขอเข้า: ผู้ใช้ที่ยังไม่มีครอบครัวขอเข้าครอบครัวของคนในชุมชน (จากโปรไฟล์)
//         → Owner อนุมัติ/ปฏิเสธ
// (ยังเข้าด้วยรหัสเชิญได้เหมือนเดิม: POST /api/families/join)
// =======================================================

class FamilyInvitationController extends Controller
{
    // GET /api/family-invitations
    // received: คำเชิญถึงเรา / sent: คำขอของเรา
    // requests: คำขอเข้าครอบครัวของเรา (เฉพาะ Owner) / invited: คนที่ครอบครัวเราชวนไว้
    public function index(Request $request)
    {
        $me = $request->user();

        $membership = FamilyMember::where('user_id', $me->id)->first();

        $relations = ['family.owner:id,name,profile_photo', 'user:id,name,profile_photo', 'creator:id,name,profile_photo'];

        $present = fn ($items) => $items->map(fn (FamilyInvitation $item) => $item->payload())->values();

        $isOwner = $membership?->role === 'owner';

        return response()->json([
            'status' => true,
            'has_family' => $membership !== null,
            'is_owner' => $isOwner,
            'received' => $present(FamilyInvitation::pending()
                ->where('type', FamilyInvitation::INVITE)
                ->where('user_id', $me->id)
                ->with($relations)
                ->latest('id')
                ->get()),
            'sent' => $present(FamilyInvitation::pending()
                ->where('type', FamilyInvitation::REQUEST)
                ->where('user_id', $me->id)
                ->with($relations)
                ->latest('id')
                ->get()),
            'requests' => $present($isOwner
                ? FamilyInvitation::pending()
                    ->where('type', FamilyInvitation::REQUEST)
                    ->where('family_id', $membership->family_id)
                    ->with($relations)
                    ->latest('id')
                    ->get()
                : collect()),
            'invited' => $present($membership
                ? FamilyInvitation::pending()
                    ->where('type', FamilyInvitation::INVITE)
                    ->where('family_id', $membership->family_id)
                    ->with($relations)
                    ->latest('id')
                    ->get()
                : collect()),
        ]);
    }

    // POST /api/family-invitations {user_id | email}
    // คนในครอบครัวชวนผู้ใช้ที่ยังไม่มีครอบครัว
    public function invite(Request $request)
    {
        $data = $request->validate([
            'user_id' => 'required_without:email|nullable|integer',
            'email' => 'required_without:user_id|nullable|email|max:255',
        ], [
            'email.email' => 'รูปแบบอีเมลไม่ถูกต้อง',
        ]);

        $me = $request->user();

        $membership = FamilyMember::where('user_id', $me->id)->first();

        if (!$membership) {
            return $this->fail('สร้างหรือเข้าร่วมครอบครัวก่อน จึงจะชวนคนอื่นได้', 403);
        }

        // ค้นด้วยอีเมลตรงตัวเท่านั้น (ไม่ให้ค้นรายชื่อผู้ใช้)
        $target = isset($data['user_id'])
            ? User::find($data['user_id'])
            : User::where('email', Str::lower(trim($data['email'])))->first();

        if (!$target) {
            return $this->fail('ไม่พบผู้ใช้นี้ ตรวจสอบอีเมลแล้วลองใหม่', 404);
        }

        if ((int) $target->id === (int) $me->id) {
            return $this->fail('ชวนตัวเองไม่ได้', 422);
        }

        if ($this->blockedBetween($me, $target)) {
            return $this->fail('ชวนผู้ใช้นี้ไม่ได้', 403);
        }

        if (FamilyMember::where('user_id', $target->id)->exists()) {
            return $this->fail($target->name . ' มีครอบครัวอยู่แล้ว', 409);
        }

        $family = Family::find($membership->family_id);

        // เขาขอเข้าครอบครัวเราไว้อยู่แล้ว → ชวน = รับเข้าเลย (เฉพาะ Owner)
        $theirRequest = FamilyInvitation::pending()
            ->where('type', FamilyInvitation::REQUEST)
            ->where('family_id', $family->id)
            ->where('user_id', $target->id)
            ->first();

        if ($theirRequest && $membership->role === 'owner') {
            return $this->approve($theirRequest, $me);
        }

        $invitation = FamilyInvitation::pending()
            ->where('type', FamilyInvitation::INVITE)
            ->where('family_id', $family->id)
            ->where('user_id', $target->id)
            ->first();

        if (!$invitation) {
            $invitation = FamilyInvitation::create([
                'family_id' => $family->id,
                'user_id' => $target->id,
                'created_by' => $me->id,
                'type' => FamilyInvitation::INVITE,
                'status' => FamilyInvitation::PENDING,
            ]);

            AppNotification::create([
                'user_id' => $target->id,
                'family_id' => null,
                'type' => 'family_invite',
                'title' => 'คำเชิญเข้าครอบครัว',
                'message' => $me->name . ' ชวนคุณเข้าครอบครัว ' . $family->name,
                'data' => ['invitation_id' => $invitation->id],
                'is_read' => false,
            ]);
        }

        return response()->json([
            'status' => true,
            'message' => 'ส่งคำเชิญถึง ' . $target->name . ' แล้ว',
            'invitation' => $invitation->load(['family.owner', 'user', 'creator'])->payload(),
        ]);
    }

    // POST /api/users/{user}/family-request
    // ผู้ใช้ที่ยังไม่มีครอบครัว ขอเข้าครอบครัวของ {user}
    public function request(Request $request, User $user)
    {
        $me = $request->user();

        if (FamilyMember::where('user_id', $me->id)->exists()) {
            return $this->fail('คุณมีครอบครัวอยู่แล้ว', 409);
        }

        $theirMembership = FamilyMember::where('user_id', $user->id)->first();

        if ((int) $user->id === (int) $me->id || !$theirMembership) {
            return $this->fail('ผู้ใช้นี้ยังไม่มีครอบครัว', 404);
        }

        if ($this->blockedBetween($me, $user)) {
            return $this->fail('ขอเข้าครอบครัวนี้ไม่ได้', 403);
        }

        $family = Family::find($theirMembership->family_id);

        // ครอบครัวนี้ชวนเราไว้อยู่แล้ว → ขอเข้า = รับคำเชิญเลย
        $theirInvite = FamilyInvitation::pending()
            ->where('type', FamilyInvitation::INVITE)
            ->where('family_id', $family->id)
            ->where('user_id', $me->id)
            ->first();

        if ($theirInvite) {
            return $this->approve($theirInvite, $me);
        }

        $invitation = FamilyInvitation::pending()
            ->where('type', FamilyInvitation::REQUEST)
            ->where('family_id', $family->id)
            ->where('user_id', $me->id)
            ->first();

        if (!$invitation) {
            $invitation = FamilyInvitation::create([
                'family_id' => $family->id,
                'user_id' => $me->id,
                'created_by' => $me->id,
                'type' => FamilyInvitation::REQUEST,
                'status' => FamilyInvitation::PENDING,
            ]);

            AppNotification::create([
                'user_id' => $family->owner_id,
                'family_id' => $family->id,
                'type' => 'family_request',
                'title' => 'คำขอเข้าครอบครัว',
                'message' => $me->name . ' ขอเข้าร่วมครอบครัว ' . $family->name,
                'data' => ['invitation_id' => $invitation->id, 'user_id' => $me->id],
                'is_read' => false,
            ]);
        }

        return response()->json([
            'status' => true,
            'message' => 'ส่งคำขอแล้ว รอเจ้าของครอบครัวอนุมัติ',
            'invitation' => $invitation->load(['family.owner', 'user', 'creator'])->payload(),
        ]);
    }

    // POST /api/family-invitations/{invitation}/accept
    // คำเชิญ: ผู้ถูกชวนกดรับ / คำขอ: Owner อนุมัติ
    public function accept(Request $request, FamilyInvitation $invitation)
    {
        $me = $request->user();

        if (!$this->canRespond($invitation, $me)) {
            return $this->fail('ไม่พบคำเชิญนี้', 404);
        }

        return $this->approve($invitation, $me);
    }

    // POST /api/family-invitations/{invitation}/decline
    public function decline(Request $request, FamilyInvitation $invitation)
    {
        $me = $request->user();

        if (!$this->canRespond($invitation, $me)) {
            return $this->fail('ไม่พบคำเชิญนี้', 404);
        }

        $invitation->update([
            'status' => FamilyInvitation::DECLINED,
            'responded_by' => $me->id,
            'responded_at' => now(),
        ]);

        return response()->json([
            'status' => true,
            'message' => $invitation->type === FamilyInvitation::INVITE
                ? 'ปฏิเสธคำเชิญแล้ว'
                : 'ปฏิเสธคำขอแล้ว',
        ]);
    }

    // DELETE /api/family-invitations/{invitation}
    // ยกเลิกคำเชิญที่เราส่ง / คำขอของเรา (Owner ยกเลิกคำเชิญของครอบครัวได้ด้วย)
    public function cancel(Request $request, FamilyInvitation $invitation)
    {
        $me = $request->user();

        $isOwner = FamilyMember::where('family_id', $invitation->family_id)
            ->where('user_id', $me->id)
            ->where('role', 'owner')
            ->exists();

        $allowed = $invitation->isPending() && (
            (int) $invitation->created_by === (int) $me->id
            || ($invitation->type === FamilyInvitation::INVITE && $isOwner)
        );

        if (!$allowed) {
            return $this->fail('ไม่พบคำเชิญนี้', 404);
        }

        $invitation->update([
            'status' => FamilyInvitation::CANCELED,
            'responded_by' => $me->id,
            'responded_at' => now(),
        ]);

        return response()->json([
            'status' => true,
            'message' => 'ยกเลิกแล้ว',
        ]);
    }

    // =====================================================
    // Helpers
    // =====================================================

    // คำเชิญ → ผู้ถูกชวนตอบ / คำขอ → Owner ของครอบครัวนั้นตอบ
    private function canRespond(FamilyInvitation $invitation, User $me): bool
    {
        if (!$invitation->isPending()) {
            return false;
        }

        if ($invitation->type === FamilyInvitation::INVITE) {
            return (int) $invitation->user_id === (int) $me->id;
        }

        return FamilyMember::where('family_id', $invitation->family_id)
            ->where('user_id', $me->id)
            ->where('role', 'owner')
            ->exists();
    }

    // รับเข้าครอบครัว
    private function approve(FamilyInvitation $invitation, User $responder)
    {
        $user = $invitation->user;

        $family = $invitation->family;

        if (!$user || !$family) {
            return $this->fail('ไม่พบคำเชิญนี้', 404);
        }

        // ระหว่างรอ เขาเข้าครอบครัวอื่นไปแล้ว
        if (FamilyMember::where('user_id', $user->id)->exists()) {
            $invitation->update([
                'status' => FamilyInvitation::CANCELED,
                'responded_at' => now(),
            ]);

            return $this->fail(
                (int) $user->id === (int) $responder->id
                    ? 'คุณมีครอบครัวอยู่แล้ว ออกจากครอบครัวเดิมก่อน'
                    : $user->name . ' เข้าครอบครัวอื่นไปแล้ว',
                409
            );
        }

        DB::transaction(function () use ($invitation, $user, $family, $responder) {
            FamilyMember::create([
                'family_id' => $family->id,
                'user_id' => $user->id,
                'role' => 'member',
            ]);

            $invitation->update([
                'status' => FamilyInvitation::ACCEPTED,
                'responded_by' => $responder->id,
                'responded_at' => now(),
            ]);

            // เข้าครอบครัวได้แล้ว → คำเชิญ/คำขออื่นของคนนี้ไม่ใช้แล้ว
            FamilyInvitation::closePendingFor($user, $invitation->id);

            if ($invitation->type === FamilyInvitation::REQUEST) {
                // Owner อนุมัติ → บอกคนที่ขอ
                AppNotification::create([
                    'user_id' => $user->id,
                    'family_id' => $family->id,
                    'type' => 'family_request_accepted',
                    'title' => 'เข้าร่วมครอบครัวแล้ว',
                    'message' => 'คำขอเข้าครอบครัว ' . $family->name . ' ได้รับการอนุมัติ',
                    'data' => ['family_id' => $family->id],
                    'is_read' => false,
                ]);
            } elseif ((int) $family->owner_id !== (int) $user->id) {
                // รับคำเชิญ → บอก Owner เหมือนเข้าด้วยรหัส
                AppNotification::create([
                    'user_id' => $family->owner_id,
                    'family_id' => $family->id,
                    'type' => 'member_joined',
                    'title' => 'สมาชิกใหม่',
                    'message' => $user->name . ' เข้าร่วมครอบครัวแล้ว',
                    'data' => ['user_id' => $user->id],
                    'is_read' => false,
                ]);
            }
        });

        return response()->json([
            'status' => true,
            'message' => $invitation->type === FamilyInvitation::REQUEST
                && (int) $responder->id !== (int) $user->id
                ? 'รับ ' . $user->name . ' เข้าครอบครัวแล้ว'
                : 'เข้าร่วมครอบครัว ' . $family->name . ' แล้ว',
            'joined' => true,
        ]);
    }

    private function blockedBetween(User $a, User $b): bool
    {
        return UserBlock::where(function ($query) use ($a, $b) {
            $query->where('user_id', $a->id)->where('blocked_user_id', $b->id);
        })
            ->orWhere(function ($query) use ($a, $b) {
                $query->where('user_id', $b->id)->where('blocked_user_id', $a->id);
            })
            ->exists();
    }

    private function fail(string $message, int $status)
    {
        return response()->json([
            'status' => false,
            'message' => $message,
        ], $status);
    }
}
