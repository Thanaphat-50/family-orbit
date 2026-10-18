<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Models\UserBlock;
use Illuminate\Http\Request;

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
}
