<?php

namespace App\Http\Controllers;

use App\Models\Comment;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\PostLike;
use App\Models\User;
use App\Models\UserBlock;
use App\Models\UserReport;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class CommunityController extends Controller
{
    // =====================================================
    // POST /api/community/accept-terms
    // ยอมรับกฎชุมชน (ต้องทำก่อนโพสต์ชุมชนครั้งแรก)
    // =====================================================

    public function acceptTerms(Request $request)
    {
        $user = $request->user();

        if ($user->community_terms_accepted_at === null) {
            $user->community_terms_accepted_at = now();
            $user->save();
        }

        return response()->json([
            'status' => true,
            'message' => 'ยอมรับกฎชุมชนแล้ว',
            'community_terms_accepted' => true,
        ]);
    }

    // =====================================================
    // GET /api/blocks
    // รายชื่อผู้ใช้ที่เราบล็อก
    // =====================================================

    public function blocks(Request $request)
    {
        $users = $request->user()
            ->blockedUsers()
            ->orderByPivot('created_at', 'desc')
            ->get([
                'users.id',
                'users.name',
                'users.profile_photo',
            ])
            ->map(fn (User $blocked) => [
                'id' => $blocked->id,
                'name' => $blocked->name,
                'profile_image_url' => $blocked->profile_image_url,
            ])
            ->values();

        return response()->json([
            'status' => true,
            'users' => $users,
        ]);
    }

    // =====================================================
    // POST /api/users/{user}/block
    // =====================================================

    public function block(
        Request $request,
        User $user
    ) {
        $me = $request->user();

        if ((int) $user->id === (int) $me->id) {
            return response()->json([
                'status' => false,
                'message' => 'ไม่สามารถบล็อกตัวเองได้',
            ], 422);
        }

        UserBlock::firstOrCreate([
            'user_id' => $me->id,
            'blocked_user_id' => $user->id,
        ]);

        return response()->json([
            'status' => true,
            'message' => 'บล็อก ' . $user->name . ' แล้ว',
        ]);
    }

    // =====================================================
    // DELETE /api/users/{user}/block
    // =====================================================

    public function unblock(
        Request $request,
        User $user
    ) {
        UserBlock::where(
            'user_id',
            $request->user()->id
        )
            ->where(
                'blocked_user_id',
                $user->id
            )
            ->delete();

        return response()->json([
            'status' => true,
            'message' => 'เลิกบล็อก ' . $user->name . ' แล้ว',
        ]);
    }

    // =====================================================
    // GET /api/users/{user}/profile
    // โปรไฟล์ในชุมชน (กดชื่อ/รูปในโพสต์ชุมชน)
    // ไม่ส่งอีเมลหรือชื่อครอบครัว
    // =====================================================

    public function profile(
        Request $request,
        User $user
    ) {
        $me = $request->user();

        $membership = FamilyMember::where('user_id', $me->id)->first();

        if (!$membership) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่ได้อยู่ในครอบครัว',
            ], 403);
        }

        $isMe = (int) $user->id === (int) $me->id;

        $isFamily = !$isMe && FamilyMember::where('family_id', $membership->family_id)
            ->where('user_id', $user->id)
            ->exists();

        if (!$isMe && !$isFamily && !$this->hasCommunityActivity($user)) {
            return $this->profileNotFound();
        }

        $blockedIds = $me->blockedUsers()->pluck('users.id');

        // นับเฉพาะโพสต์ที่เราเห็นได้ในชุมชน
        $visiblePosts = fn () => Post::where('user_id', $user->id)
            ->visibleInCommunityTo($me, $blockedIds);

        return response()->json([
            'status' => true,
            'profile' => [
                'id' => $user->id,
                'name' => $user->name,
                'profile_image_url' => $user->profile_image_url,
                'joined_at' => $user->created_at?->toIso8601String(),
                'community_posts' => $visiblePosts()->count(),
                'likes_received' => PostLike::whereIn('post_id', $visiblePosts()->select('id'))->count(),
                'is_me' => $isMe,
                'is_family' => $isFamily,
                'blocked' => $blockedIds->contains($user->id),
            ],
        ]);
    }

    // =====================================================
    // POST /api/users/{user}/report
    // รายงานผู้ใช้ (Admin ตรวจในหน้าผู้ใช้)
    // =====================================================

    public function report(
        Request $request,
        User $user
    ) {
        $data = $request->validate([
            'reason' => ['required', Rule::in(array_keys(UserReport::REASONS))],
            'details' => 'nullable|string|max:1000',
        ]);

        $me = $request->user();

        if ((int) $user->id === (int) $me->id) {
            return response()->json([
                'status' => false,
                'message' => 'ไม่สามารถรายงานตัวเองได้',
            ], 422);
        }

        if (!FamilyMember::where('user_id', $me->id)->exists()) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่ได้อยู่ในครอบครัว',
            ], 403);
        }

        if (!$this->hasCommunityActivity($user)) {
            return $this->profileNotFound();
        }

        // รายงานซ้ำไม่นับเพิ่ม
        UserReport::firstOrCreate(
            [
                'reported_user_id' => $user->id,
                'user_id' => $me->id,
            ],
            [
                'reason' => $data['reason'],
                'details' => $data['details'] ?? null,
            ]
        );

        return response()->json([
            'status' => true,
            'message' => 'ขอบคุณที่รายงาน ทีมงานจะตรวจสอบโดยเร็ว',
        ]);
    }

    // เคยโพสต์หรือแสดงความคิดเห็นในชุมชน (ที่ไม่ถูกซ่อน)
    // คนที่ไม่เคยอยู่ในชุมชน → คนนอกครอบครัวเปิดดูโปรไฟล์จาก id ไม่ได้
    private function hasCommunityActivity(User $user): bool
    {
        $postedInCommunity = Post::where('user_id', $user->id)
            ->where('visibility', 'community')
            ->whereNull('hidden_at')
            ->exists();

        if ($postedInCommunity) {
            return true;
        }

        return Comment::where('user_id', $user->id)
            ->whereNull('hidden_at')
            ->whereHas('post', function ($posts) {
                $posts->where('visibility', 'community')
                    ->whereNull('hidden_at');
            })
            ->exists();
    }

    private function profileNotFound()
    {
        return response()->json([
            'status' => false,
            'message' => 'ไม่พบผู้ใช้นี้',
        ], 404);
    }
}
