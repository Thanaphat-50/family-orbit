<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\PostLike;
use App\Models\PostReport;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

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
    //                  &category=qa กรองตามหมวด (ไม่ส่ง = ทุกหมวด)
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
            $data = $request->validate([
                'category' => ['nullable', Rule::in(Post::CATEGORIES)],
            ]);

            return $this->communityFeed($user, $data['category'] ?? null);
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
            ->tap(fn ($query) => $this->withLikeInfo($query, $user))
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

    private function communityFeed(User $user, ?string $category)
    {
        $blockedIds = $user->blockedUsers()->pluck('users.id');

        $paginator = Post::where('visibility', 'community')
            ->when($category, fn ($query) => $query->where('category', $category))
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
            ->tap(fn ($query) => $this->withLikeInfo($query, $user))
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->simplePaginate(self::COMMUNITY_PAGE_SIZE);

        $posts = collect($paginator->items())
            ->map(fn ($post) => $this->withOwnership($post, $user))
            ->values();

        return response()->json([
            'status' => true,
            'scope' => 'community',
            'category' => $category,
            'current_user' => $this->currentUserPayload($user),
            'posts' => $posts,
            'page' => $paginator->currentPage(),
            'has_more' => $paginator->hasMorePages(),
        ]);
    }

    // =====================================================
    // สร้าง Post
    // visibility: family (ค่าเริ่มต้น) / community
    // category:   ใช้เฉพาะโพสต์ชุมชน (ค่าเริ่มต้น general)
    // =====================================================

    public function store(Request $request)
    {
        $data = $request->validate([
            'content' => 'required|string|max:5000',
            'visibility' => 'nullable|in:family,community',
            'category' => ['nullable', Rule::in(Post::CATEGORIES)],
        ]);

        $visibility = $data['visibility'] ?? 'family';

        // โพสต์ครอบครัวไม่เก็บหมวด
        $category = $visibility === 'community'
            ? ($data['category'] ?? 'general')
            : null;

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
                $category,
                $user,
                $membership
            ) {
                $post = Post::create([
                    'family_id' =>
                        $membership->family_id,
                    'user_id' => $user->id,
                    'visibility' => $visibility,
                    'category' => $category,
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
        $post->setAttribute('likes_count', 0);
        $post->setAttribute('liked_by_me', false);

        return response()->json([
            'status' => true,
            'message' => 'สร้างโพสต์สำเร็จ',
            'post' => $post,
        ], 201);
    }

    // =====================================================
    // ถูกใจ / ยกเลิกถูกใจ
    // POST /api/posts/{post}/like (กดซ้ำ = ยกเลิก)
    // =====================================================

    public function like(
        Request $request,
        Post $post
    ) {
        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        if (!$this->canInteract($post, $membership)) {
            return response()->json([
                'status' => false,
                'message' => 'คุณไม่มีสิทธิ์ถูกใจโพสต์นี้',
            ], 403);
        }

        $existing = PostLike::where('post_id', $post->id)
            ->where('user_id', $user->id)
            ->first();

        if ($existing) {
            $existing->delete();
        } else {
            PostLike::firstOrCreate([
                'post_id' => $post->id,
                'user_id' => $user->id,
            ]);
        }

        return response()->json([
            'status' => true,
            'liked' => $existing === null,
            'likes_count' => $post->likes()->count(),
        ]);
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

    // ผู้ใช้ถูกใจ/โต้ตอบกับโพสต์นี้ได้หรือไม่
    // - โพสต์ชุมชน: ต้องมีครอบครัว และโพสต์ต้องไม่ถูกซ่อน
    // - โพสต์ครอบครัว: ต้องอยู่ครอบครัวเดียวกับโพสต์
    private function canInteract(Post $post, ?FamilyMember $membership): bool
    {
        if (!$membership) {
            return false;
        }

        if ($post->isCommunity()) {
            return $post->hidden_at === null;
        }

        return (int) $post->family_id === (int) $membership->family_id;
    }

    // จำนวนถูกใจ (likes_count) และเราถูกใจแล้วหรือยัง (liked_by_me)
    private function withLikeInfo($query, User $user)
    {
        return $query->withCount('likes')
            ->withExists([
                'likes as liked_by_me' => fn ($likes) => $likes->where('user_id', $user->id),
            ]);
    }

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
