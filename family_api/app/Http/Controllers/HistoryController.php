<?php

namespace App\Http\Controllers;

use App\Models\Interaction;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

// =======================================================
// ประวัติการใช้งานของเรา (ถูกใจ / ความคิดเห็น / แชร์ / ติดตาม)
// เห็นได้เฉพาะเจ้าของ และล้างได้ทุกเมื่อ
// =======================================================

class HistoryController extends Controller
{
    private const PAGE_SIZE = 30;

    // GET /api/me/history?page=N
    public function index(Request $request)
    {
        $paginator = $request->user()
            ->interactions()
            ->with([
                'post:id,user_id,visibility,content,shared_post_id',
                'post.user:id,name,profile_photo',
                'post.images',
                'targetUser:id,name,profile_photo',
            ])
            ->latest('id')
            ->simplePaginate(self::PAGE_SIZE);

        $items = collect($paginator->items())->map(fn (Interaction $item) => [
            'id' => $item->id,
            'type' => $item->type,
            'channel' => $item->meta['channel'] ?? null,
            'excerpt' => $item->meta['excerpt'] ?? null,
            'created_at' => $item->created_at?->toIso8601String(),
            'post' => $item->post ? [
                'id' => $item->post->id,
                'visibility' => $item->post->visibility,
                'content' => Str::limit(trim((string) $item->post->content), 120),
                'image_url' => $item->post->images->first()?->url,
                'user' => $item->post->user?->only(['id', 'name', 'profile_image_url']),
            ] : null,
            'target_user' => $item->targetUser?->only(['id', 'name', 'profile_image_url']),
        ])->values();

        return response()->json([
            'status' => true,
            'items' => $items,
            'page' => $paginator->currentPage(),
            'has_more' => $paginator->hasMorePages(),
        ]);
    }

    // DELETE /api/me/history → ล้างประวัติทั้งหมด
    // (การถูกใจ/การติดตามจริงยังอยู่ แค่ไม่ใช้จัดฟีดและแนะนำแล้ว)
    public function clear(Request $request)
    {
        $request->user()->interactions()->delete();

        return response()->json([
            'status' => true,
            'message' => 'ล้างประวัติการใช้งานแล้ว',
        ]);
    }
}
