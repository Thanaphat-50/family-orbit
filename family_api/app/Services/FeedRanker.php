<?php

namespace App\Services;

use App\Models\Interaction;
use App\Models\Post;
use App\Models\User;
use Illuminate\Support\Collection;

// =======================================================
// ฟีดชุมชน "สำหรับคุณ"
//
// คะแนนของแต่ละโพสต์ = ความนิยม × ความสนใจของเรา ÷ ความเก่า
// - ความนิยม: ถูกใจ + ความคิดเห็น (×2) + แชร์ (×3)
// - ความสนใจ: หมวดที่เราชอบ, คนที่เราเคยกดถูกใจ/คอมเมนต์/แชร์, คนที่เราติดตาม
//   (คิดจากประวัติการใช้งาน 60 วันล่าสุด)
// - โพสต์ที่เรากดไปแล้ว / โพสต์ของเราเอง → ลดลำดับ ให้เห็นของใหม่ก่อน
// =======================================================

class FeedRanker
{
    // ใช้ประวัติย้อนหลังกี่วัน
    private const SIGNAL_DAYS = 60;

    // นำโพสต์ชุมชนล่าสุดกี่โพสต์มาจัดอันดับ
    private const CANDIDATE_LIMIT = 400;

    private const WEIGHTS = [
        Interaction::LIKE => 1,
        Interaction::COMMENT => 2,
        Interaction::SHARE => 3,
    ];

    // id โพสต์ชุมชน เรียงจากน่าสนใจที่สุด
    public function rankedIds(User $user, Collection $blockedIds, ?string $category = null): Collection
    {
        [$categoryScores, $authorScores, $engagedPostIds] = $this->interests($user);

        $following = $user->following()->pluck('users.id')->flip();

        $totalCategory = max(1, array_sum($categoryScores));

        $now = now();

        return Post::query()
            ->visibleInCommunityTo($user, $blockedIds)
            ->when($category, fn ($query) => $query->where('category', $category))
            ->withCount(['likes', 'comments', 'shares'])
            ->latest('id')
            ->limit(self::CANDIDATE_LIMIT)
            ->get(['id', 'user_id', 'category', 'created_at'])
            ->map(function (Post $post) use (
                $user,
                $categoryScores,
                $authorScores,
                $engagedPostIds,
                $following,
                $totalCategory,
                $now
            ) {
                $hours = max(0, $post->created_at->diffInMinutes($now)) / 60;

                $popularity = log(2 + $post->likes_count + 2 * $post->comments_count + 3 * $post->shares_count);

                $interest = 1 + 2 * (($categoryScores[$post->category] ?? 0) / $totalCategory);

                $author = 1 + min(1.5, 0.3 * ($authorScores[$post->user_id] ?? 0));

                $follow = $following->has($post->user_id) ? 3.0 : 1.0;

                $own = (int) $post->user_id === (int) $user->id ? 0.6 : 1.0;

                $seen = isset($engagedPostIds[$post->id]) ? 0.5 : 1.0;

                return [
                    'id' => $post->id,
                    // +4 ชั่วโมง: โพสต์ใหม่มาก ๆ ไม่แซงเรื่องที่เราสนใจง่ายเกินไป
                    'score' => $popularity * $interest * $author * $follow * $own * $seen
                        / pow($hours + 4, 1.2),
                ];
            })
            ->sort(fn ($a, $b) => [$b['score'], $b['id']] <=> [$a['score'], $a['id']])
            ->pluck('id')
            ->values();
    }

    // [คะแนนตามหมวด, คะแนนตามคนโพสต์, โพสต์ที่เคยกดแล้ว]
    public function interests(User $user): array
    {
        $categoryScores = [];
        $authorScores = [];
        $engagedPostIds = [];

        $signals = Interaction::where('user_id', $user->id)
            ->whereIn('type', array_keys(self::WEIGHTS))
            ->whereNotNull('post_id')
            ->where('created_at', '>=', now()->subDays(self::SIGNAL_DAYS))
            ->with('post:id,user_id,category')
            ->get();

        foreach ($signals as $signal) {
            $post = $signal->post;

            if (!$post) {
                continue;
            }

            $weight = self::WEIGHTS[$signal->type];

            $engagedPostIds[$post->id] = true;

            if ($post->category) {
                $categoryScores[$post->category] = ($categoryScores[$post->category] ?? 0) + $weight;
            }

            if ((int) $post->user_id !== (int) $user->id) {
                $authorScores[$post->user_id] = ($authorScores[$post->user_id] ?? 0) + $weight;
            }
        }

        return [$categoryScores, $authorScores, $engagedPostIds];
    }
}
