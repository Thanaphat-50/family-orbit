<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\PostReport;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PostController extends Controller
{
    // จำนวนโพสต์ชุมชนต่อหน้า
    private const COMMUNITY_PAGE_SIZE = 20;

    // ข้อมูลผู้ใช้ที่ส่งไปกับโพสต์/ความคิดเห็น (ไม่ส่ง email)
    private const USER_COLUMNS = 'id,name,profile_photo';

    // =====================================================
    // ดู Post
    //
    // ?scope=family    (ค่าเริ่มต้น) โพสต์ในครอบครัว
    // ?scope=community &page=N      โพสต์ชุมชนของทุกคน
    // =====================================================

    public function index(Request $request)
    {
        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        if (!$membership) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่ได้อยู่ในครอบครัว',
                'posts' => [],
            ], 403);
        }

        if ($request->query('scope') === 'community') {
            return $this->communityFeed($user);
        }

        $posts = Post::where(
            'family_id',
            $membership->family_id
        )
            ->where('visibility', 'family')
            ->with([
                'user:' . self::USER_COLUMNS,
                'comments.user:' . self::USER_COLUMNS,
            ])
            ->latest()
            ->get()
            ->map(fn ($post) => $this->withOwnership($post, $user));

        return response()->json([
            'status' => true,
            'scope' => 'family',
            'current_user' => $this->currentUserPayload($user),
            'posts' => $posts,
        ]);
    }

    // =====================================================
    // ฟีดชุมชน
    // - ไม่แสดงโพสต์ที่ถูกซ่อน
    // - ไม่แสดงโพสต์ที่เรารายงานไปแล้ว
    // - ไม่แสดงโพสต์/ความคิดเห็นของคนที่เราบล็อก
    // =====================================================

    private function communityFeed(User $user)
    {
        $blockedIds = $user->blockedUsers()->pluck('users.id');

        $paginator = Post::where('visibility', 'community')
            ->whereNull('hidden_at')
            ->whereDoesntHave('reports', function ($query) use ($user) {
                $query->where('user_id', $user->id);
            })
            ->whereNotIn('user_id', $blockedIds)
            ->with([
                'user:' . self::USER_COLUMNS,
                // ไม่แสดงความคิดเห็นที่ถูกซ่อน, ที่เรารายงานแล้ว
                // หรือของคนที่เราบล็อก
                'comments' => function ($query) use ($blockedIds, $user) {
                    $query->whereNull('hidden_at')
                        ->whereDoesntHave('reports', function ($reports) use ($user) {
                            $reports->where('user_id', $user->id);
                        })
                        ->whereNotIn('user_id', $blockedIds);
                },
                'comments.user:' . self::USER_COLUMNS,
            ])
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->simplePaginate(self::COMMUNITY_PAGE_SIZE);

        $posts = collect($paginator->items())
            ->map(fn ($post) => $this->withOwnership($post, $user))
            ->values();

        return response()->json([
            'status' => true,
            'scope' => 'community',
            'current_user' => $this->currentUserPayload($user),
            'posts' => $posts,
            'page' => $paginator->currentPage(),
            'has_more' => $paginator->hasMorePages(),
        ]);
    }

    // =====================================================
    // สร้าง Post
    // visibility: family (ค่าเริ่มต้น) / community
    // =====================================================

    public function store(Request $request)
    {
        $data = $request->validate([
            'content' => 'required|string|max:5000',
            'visibility' => 'nullable|in:family,community',
        ]);

        $visibility = $data['visibility'] ?? 'family';

        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        if (!$membership) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่ได้อยู่ในครอบครัว',
            ], 403);
        }

        // โพสต์ชุมชนต้องยอมรับกฎชุมชนก่อน
        if (
            $visibility === 'community'
            && $user->community_terms_accepted_at === null
        ) {
            return response()->json([
                'status' => false,
                'code' => 'terms_required',
                'message' => 'กรุณายอมรับกฎชุมชนก่อนโพสต์',
            ], 403);
        }

        $post = DB::transaction(
            function () use (
                $data,
                $visibility,
                $user,
                $membership
            ) {
                $post = Post::create([
                    'family_id' =>
                        $membership->family_id,
                    'user_id' => $user->id,
                    'visibility' => $visibility,
                    'content' => $data['content'],
                ]);

                // โพสต์ชุมชนไม่แจ้งเตือนใคร (กันสแปม)
                if ($visibility !== 'family') {
                    return $post;
                }

                // แจ้งสมาชิกคนอื่นใน Family
                $memberIds =
                    FamilyMember::where(
                        'family_id',
                        $membership->family_id
                    )
                        ->where(
                            'user_id',
                            '!=',
                            $user->id
                        )
                        ->pluck('user_id');

                foreach ($memberIds as $memberId) {
                    AppNotification::create([
                        'user_id' => $memberId,
                        'family_id' =>
                            $membership->family_id,
                        'type' => 'new_post',
                        'title' => 'โพสต์ใหม่',
                        'message' =>
                            $user->name .
                            ' สร้างโพสต์ใหม่',
                        'data' => [
                            'post_id' => $post->id,
                        ],
                        'is_read' => false,
                    ]);
                }

                return $post;
            }
        );

        $post->load([
            'user:' . self::USER_COLUMNS,
            'comments.user:' . self::USER_COLUMNS,
        ]);

        $post->setAttribute('is_mine', true);

        return response()->json([
            'status' => true,
            'message' => 'สร้างโพสต์สำเร็จ',
            'post' => $post,
        ], 201);
    }

    // =====================================================
    // ลบ Post
    // =====================================================

    public function destroy(
        Request $request,
        Post $post
    ) {
        $user = $request->user();

        // ต้องเป็นเจ้าของ Post
        if ($post->user_id !== $user->id) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณสามารถลบได้เฉพาะโพสต์ของตัวเอง',
            ], 403);
        }

        // โพสต์ครอบครัว: ต้องยังอยู่ใน Family ของ Post นี้
        // โพสต์ชุมชน: เจ้าของลบได้เสมอ
        if (!$post->isCommunity()) {
            $membership = FamilyMember::where(
                'user_id',
                $user->id
            )
                ->where(
                    'family_id',
                    $post->family_id
                )
                ->first();

            if (!$membership) {
                return response()->json([
                    'status' => false,
                    'message' =>
                        'คุณไม่ได้อยู่ในครอบครัวของโพสต์นี้แล้ว',
                ], 403);
            }
        }

        $post->delete();

        return response()->json([
            'status' => true,
            'message' => 'ลบโพสต์สำเร็จ',
        ]);
    }

    // =====================================================
    // รายงาน Post ชุมชน
    // =====================================================

    public function report(
        Request $request,
        Post $post
    ) {
        $data = $request->validate([
            'reason' =>
                'required|in:spam,inappropriate,harassment,scam,other',
            'details' => 'nullable|string|max:1000',
        ]);

        $user = $request->user();

        $isMember = FamilyMember::where(
            'user_id',
            $user->id
        )->exists();

        if (!$isMember) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่ได้อยู่ในครอบครัว',
            ], 403);
        }

        if (!$post->isCommunity()) {
            return response()->json([
                'status' => false,
                'message' => 'รายงานได้เฉพาะโพสต์ชุมชน',
            ], 422);
        }

        if ((int) $post->user_id === (int) $user->id) {
            return response()->json([
                'status' => false,
                'message' => 'ไม่สามารถรายงานโพสต์ของตัวเองได้',
            ], 422);
        }

        // รายงานซ้ำไม่นับเพิ่ม
        PostReport::firstOrCreate(
            [
                'post_id' => $post->id,
                'user_id' => $user->id,
            ],
            [
                'reason' => $data['reason'],
                'details' => $data['details'] ?? null,
            ]
        );

        // ซ่อนอัตโนมัติเมื่อถูกรายงานครบ
        if (
            $post->hidden_at === null
            && $post->reports()->count() >= config('community.auto_hide_reports')
        ) {
            $post->hidden_at = now();
            $post->save();
        }

        return response()->json([
            'status' => true,
            'message' =>
                'ขอบคุณที่รายงาน เราจะตรวจสอบโพสต์นี้',
        ]);
    }

    // =====================================================
    // HELPERS
    // =====================================================

    // ให้แอปรู้ว่าโพสต์ไหนเป็นของเรา (แสดงปุ่มลบ)
    private function withOwnership(Post $post, User $user): Post
    {
        $post->setAttribute(
            'is_mine',
            (int) $post->user_id === (int) $user->id
        );

        return $post;
    }

    private function currentUserPayload(User $user): array
    {
        return [
            ...$user->only([
                'id',
                'name',
                'profile_image_url',
            ]),
            'community_terms_accepted' =>
                $user->community_terms_accepted_at !== null,
        ];
    }
}
