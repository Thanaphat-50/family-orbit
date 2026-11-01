<?php

namespace App\Http\Controllers;

use App\Models\Interaction;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

// =======================================================
// ประวัติการใช้งานของเรา (ถูกใจ / ความคิดเห็น / แชร์ / ติดตาม)
// เห็นได้เฉพาะเจ้าของ และล้างได้ทุกเมื่อ
// ถูกใจ / ความคิดเห็น / แชร์ แยกได้อีกชั้น: โพสต์ทั่วไป กับ วิดีโอ (media)
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

    // ประเภทที่เกี่ยวกับโพสต์ (แยก โพสต์ / วิดีโอ ได้)
    private const MEDIA_TYPES = [
        Interaction::LIKE,
        Interaction::COMMENT,
        Interaction::SHARE,
    ];

    private const MEDIA = ['post', 'video'];

    // GET /api/me/history?type=like&media=video&page=N
    // ไม่ส่ง type = ทุกประเภท / ไม่ส่ง media = ทั้งโพสต์และวิดีโอ
    public function index(Request $request)
    {
        $data = $request->validate([
            'type' => ['nullable', Rule::in(self::TYPES)],
            'media' => ['nullable', Rule::in(self::MEDIA)],
        ]);

        $type = $data['type'] ?? null;

        $media = $data['media'] ?? null;

        $paginator = $request->user()
            ->interactions()
            ->when($type, fn ($query) => $query->where('type', $type))
            ->tap(fn ($query) => $this->filterMedia($query, $media))
            ->with([
                'post:id,user_id,visibility,content,shared_post_id',
                'post.user:id,name,profile_photo',
                'post.images',
                'post.video',
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
                'has_video' => $item->post->video !== null,
                'video_thumbnail_url' => $item->post->video?->thumbnail_url,
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

        // จำนวนโพสต์ / วิดีโอ ของแต่ละแท็บ
        $mediaCount = fn (string $kind) => $request->user()
            ->interactions()
            ->whereIn('type', self::MEDIA_TYPES)
            ->tap(fn ($query) => $this->filterMedia($query, $kind))
            ->selectRaw('type, count(*) as total')
            ->groupBy('type')
            ->pluck('total', 'type');

        $postCounts = $mediaCount('post');
        $videoCounts = $mediaCount('video');

        return response()->json([
            'status' => true,
            'type' => $type,
            'media' => $media,
            'items' => $items,
            'counts' => collect(self::TYPES)
                ->mapWithKeys(fn ($key) => [$key => (int) ($counts[$key] ?? 0)]),
            'media_counts' => collect(self::MEDIA_TYPES)
                ->mapWithKeys(fn ($key) => [$key => [
                    'post' => (int) ($postCounts[$key] ?? 0),
                    'video' => (int) ($videoCounts[$key] ?? 0),
                ]]),
            'page' => $paginator->currentPage(),
            'has_more' => $paginator->hasMorePages(),
        ]);
    }

    // DELETE /api/me/history?type=like&media=video → ล้างเฉพาะส่วนนั้น (ไม่ส่ง = ทั้งหมด)
    // (การถูกใจ/การติดตามจริงยังอยู่ แค่ไม่ใช้จัดฟีดและแนะนำแล้ว)
    public function clear(Request $request)
    {
        $data = $request->validate([
            'type' => ['nullable', Rule::in(self::TYPES)],
            'media' => ['nullable', Rule::in(self::MEDIA)],
        ]);

        $request->user()
            ->interactions()
            ->when($data['type'] ?? null, fn ($query, $type) => $query->where('type', $type))
            ->tap(fn ($query) => $this->filterMedia($query, $data['media'] ?? null))
            ->delete();

        return response()->json([
            'status' => true,
            'message' => 'ล้างประวัติแล้ว',
        ]);
    }

    // video = โพสต์ที่มีวิดีโอของตัวเอง / post = โพสต์อื่น ๆ (ติดตามไม่อยู่ในทั้งสองแบบ)
    private function filterMedia($query, ?string $media): void
    {
        if ($media === 'video') {
            $query->whereHas('post.video');
        } elseif ($media === 'post') {
            $query->whereNotNull('post_id')->whereDoesntHave('post.video');
        }
    }
}
