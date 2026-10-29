<?php

namespace App\Http\Controllers;

use App\Models\Interaction;
use App\Models\User;
use App\Models\UserBlock;
use App\Services\FollowSuggester;
use Illuminate\Http\Request;

// =======================================================
// ติดตามผู้ใช้อื่น (ไม่ต้องรออนุมัติ)
// โพสต์ชุมชนของคนที่ติดตามจะขึ้นก่อนในฟีด "สำหรับคุณ"
// =======================================================

class FollowController extends Controller
{
    // GET /api/users/suggestions → คนที่อาจชอบเรื่องเดียวกับเรา
    public function suggestions(Request $request, FollowSuggester $suggester)
    {
        return response()->json([
            'status' => true,
            'users' => $suggester->suggest($request->user()),
        ]);
    }

    // POST /api/users/{user}/follow
    public function store(Request $request, User $user)
    {
        $me = $request->user();

        if ((int) $user->id === (int) $me->id) {
            return response()->json([
                'status' => false,
                'message' => 'ติดตามตัวเองไม่ได้',
            ], 422);
        }

        // บล็อกกันอยู่ (ฝั่งไหนก็ได้) → ติดตามไม่ได้
        $blocked = UserBlock::where(function ($query) use ($me, $user) {
            $query->where('user_id', $me->id)->where('blocked_user_id', $user->id);
        })
            ->orWhere(function ($query) use ($me, $user) {
                $query->where('user_id', $user->id)->where('blocked_user_id', $me->id);
            })
            ->exists();

        if ($blocked) {
            return response()->json([
                'status' => false,
                'message' => 'ติดตามผู้ใช้นี้ไม่ได้',
            ], 403);
        }

        $changes = $me->following()->syncWithoutDetaching([$user->id]);

        if ($changes['attached'] !== []) {
            Interaction::record($me, Interaction::FOLLOW, target: $user);
        }

        return $this->state($me, $user, 'ติดตาม ' . $user->name . ' แล้ว');
    }

    // DELETE /api/users/{user}/follow
    public function destroy(Request $request, User $user)
    {
        $me = $request->user();

        $me->following()->detach($user->id);

        Interaction::forget($me, Interaction::FOLLOW, target: $user);

        return $this->state($me, $user, 'เลิกติดตาม ' . $user->name . ' แล้ว');
    }

    private function state(User $me, User $user, string $message)
    {
        return response()->json([
            'status' => true,
            'message' => $message,
            'is_following' => $me->following()->whereKey($user->id)->exists(),
            'followers_count' => $user->followers()->count(),
        ]);
    }
}
