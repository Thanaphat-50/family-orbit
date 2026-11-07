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
    private const LIST_PAGE_SIZE = 30;

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

    // =====================================================
    // GET /api/me/followers?page=  คนที่ติดตามเรา
    // GET /api/me/following?page=  คนที่เราติดตาม
    // เห็นได้เฉพาะรายชื่อของตัวเอง ไม่นับคนที่บล็อกกัน (ตรงกับตัวเลขในหน้าโปรไฟล์)
    // =====================================================

    public function myFollowers(Request $request)
    {
        return $this->list($request, $request->user()->followers());
    }

    public function myFollowing(Request $request)
    {
        return $this->list($request, $request->user()->following());
    }

    private function list(Request $request, $relation)
    {
        $me = $request->user();

        $request->validate(['page' => 'nullable|integer|min:1']);

        $paginator = $relation
            ->whereNotIn('users.id', UserBlock::idsBlockedEitherWay($me))
            ->orderByPivot('created_at', 'desc')
            ->simplePaginate(self::LIST_PAGE_SIZE, ['users.id', 'users.name', 'users.profile_photo']);

        $ids = collect($paginator->items())->pluck('id');

        // เราติดตามใครในหน้านี้อยู่แล้ว / ใครติดตามเรา
        $iFollow = $me->following()->whereIn('users.id', $ids)->pluck('users.id')->flip();
        $followsMe = $me->followers()->whereIn('users.id', $ids)->pluck('users.id')->flip();

        return response()->json([
            'status' => true,
            'users' => collect($paginator->items())->map(fn (User $user) => [
                'id' => $user->id,
                'name' => $user->name,
                'profile_photo_url' => $user->profile_photo_url,
                'is_following' => $iFollow->has($user->id),
                'follows_me' => $followsMe->has($user->id),
            ])->values(),
            'page' => $paginator->currentPage(),
            'has_more' => $paginator->hasMorePages(),
        ]);
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
