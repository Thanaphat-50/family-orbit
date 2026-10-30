<?php

namespace App\Http\Controllers;

use App\Models\Interaction;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

// =======================================================
// ประวัติการใช้งานของเรา (ถูกใจ / ความคิดเห็น / แชร์ / ติดตาม)
// เห็นได้เฉพาะเจ้าของ และล้างได้ทุกเมื่อ
// =======================================================

class HistoryController extends Controller
{
    private const PAGE_SIZE = 30;

    // ประเภทที่แยกแท็บในแอป
    private const TYPES = [
        Interaction::LIKE,
        Interaction::COMMENT,
        Interaction::SHARE,
        Interaction::FOLLOW,
    ];

    // GET /api/me/history?type=like&page=N (ไม่ส่ง type = ทุกประเภท)
    public function index(Request $request)
    {
        $data = $request->validate([
            'type' => ['nullable', Rule::in(self::TYPES)],
        ]);

        $type = $data['type'] ?? null;

        $paginator = $request->user()
            ->interactions()
            ->when($type, fn ($query) => $query->where('type', $type))
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

        // จำนวนของแต่ละแท็บ
        $counts = $request->user()
            ->interactions()
            ->selectRaw('type, count(*) as total')
            ->groupBy('type')
            ->pluck('total', 'type');

        return response()->json([
            'status' => true,
            'type' => $type,
            'items' => $items,
            'counts' => collect(self::TYPES)
                ->mapWithKeys(fn ($key) => [$key => (int) ($counts[$key] ?? 0)]),
            'page' => $paginator->currentPage(),
            'has_more' => $paginator->hasMorePages(),
        ]);
    }

    // DELETE /api/me/history?type=like → ล้างเฉพาะประเภทนั้น (ไม่ส่ง = ทั้งหมด)
    // (การถูกใจ/การติดตามจริงยังอยู่ แค่ไม่ใช้จัดฟีดและแนะนำแล้ว)
    public function clear(Request $request)
    {
        $data = $request->validate([
            'type' => ['nullable', Rule::in(self::TYPES)],
        ]);

        $request->user()
            ->interactions()
            ->when($data['type'] ?? null, fn ($query, $type) => $query->where('type', $type))
            ->delete();

        return response()->json([
            'status' => true,
            'message' => 'ล้างประวัติแล้ว',
        ]);
    }
}
