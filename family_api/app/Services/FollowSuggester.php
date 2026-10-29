<?php

namespace App\Services;

use App\Models\FamilyMember;
use App\Models\Interaction;
use App\Models\Post;
use App\Models\PostLike;
use App\Models\User;
use App\Models\UserBlock;
use Illuminate\Support\Collection;

// =======================================================
// แนะนำคนที่อาจชอบเรื่องเดียวกับเรา (จากประวัติการใช้งาน)
//
// - กดถูกใจ/คอมเมนต์/แชร์โพสต์เดียวกันกับเรา        (×3 ต่อโพสต์)
// - เราเคยกดถูกใจ/คอมเมนต์/แชร์โพสต์ของเขา           (×2 ต่อครั้ง)
// - โพสต์ในหมวดที่เราสนใจที่สุด (30 วัน)               (×1 ต่อโพสต์)
// ยังไม่มีประวัติ → แนะนำคนที่โพสต์ได้รับถูกใจมากในชุมชน
// ไม่แนะนำ: ตัวเอง คนในครอบครัว คนที่ติดตามแล้ว คนที่บล็อกกัน
// =======================================================

class FollowSuggester
{
    private const SIGNAL_DAYS = 60;

    public function __construct(private FeedRanker $ranker)
    {
    }

    public function suggest(User $user, int $limit = 10): Collection
    {
        $excluded = $this->excludedIds($user);

        [$categoryScores, $authorScores, $engagedPostIds] = $this->ranker->interests($user);

        $scores = [];
        $reasons = [];

        $add = function (int $userId, float $points, string $reason, int $priority) use (&$scores, &$reasons, $excluded) {
            if (isset($excluded[$userId])) {
                return;
            }

            $scores[$userId] = ($scores[$userId] ?? 0) + $points;

            // เก็บเหตุผลที่หนักแน่นที่สุดไว้แสดง
            if (!isset($reasons[$userId]) || $priority > $reasons[$userId]['priority']) {
                $reasons[$userId] = ['text' => $reason, 'priority' => $priority];
            }
        };

        // 1) กดโพสต์เดียวกันกับเรา
        if ($engagedPostIds !== []) {
            Interaction::whereIn('post_id', array_keys($engagedPostIds))
                ->where('user_id', '!=', $user->id)
                ->whereIn('type', [Interaction::LIKE, Interaction::COMMENT, Interaction::SHARE])
                ->where('created_at', '>=', now()->subDays(self::SIGNAL_DAYS))
                ->selectRaw('user_id, count(distinct post_id) as overlap')
                ->groupBy('user_id')
                ->get()
                ->each(fn ($row) => $add(
                    (int) $row->user_id,
                    3 * $row->overlap,
                    'ชอบโพสต์เดียวกับคุณ ' . $row->overlap . ' โพสต์',
                    3
                ));
        }

        // 2) คนที่เราเคยกดโพสต์ของเขา
        foreach ($authorScores as $authorId => $points) {
            $add((int) $authorId, 2 * $points, 'คุณเคยถูกใจโพสต์ของเขา', 2);
        }

        // 3) โพสต์ในหมวดที่เราสนใจที่สุด
        arsort($categoryScores);

        $topCategory = array_key_first($categoryScores);

        if ($topCategory !== null) {
            Post::where('visibility', 'community')
                ->whereNull('hidden_at')
                ->where('category', $topCategory)
                ->where('created_at', '>=', now()->subDays(30))
                ->selectRaw('user_id, count(*) as total')
                ->groupBy('user_id')
                ->get()
                ->each(fn ($row) => $add(
                    (int) $row->user_id,
                    min(3, (int) $row->total),
                    'โพสต์หมวด' . (Post::CATEGORY_LABELS[$topCategory] ?? $topCategory) . ' ที่คุณสนใจ',
                    1
                ));
        }

        // ยังไม่มีประวัติ → คนที่โพสต์ได้รับถูกใจมากในชุมชน
        if ($scores === []) {
            PostLike::join('posts', 'posts.id', '=', 'post_likes.post_id')
                ->where('posts.visibility', 'community')
                ->whereNull('posts.hidden_at')
                ->where('post_likes.created_at', '>=', now()->subDays(30))
                ->selectRaw('posts.user_id as author_id, count(*) as total')
                ->groupBy('posts.user_id')
                ->orderByDesc('total')
                ->limit($limit * 2)
                ->get()
                ->each(fn ($row) => $add(
                    (int) $row->author_id,
                    (float) $row->total,
                    'โพสต์ได้รับถูกใจมากในชุมชน',
                    0
                ));
        }

        arsort($scores);

        $ids = array_slice(array_keys($scores), 0, $limit);

        $users = User::whereIn('id', $ids)
            ->withCount('followers')
            ->get()
            ->keyBy('id');

        return collect($ids)
            ->filter(fn ($id) => $users->has($id))
            ->map(fn ($id) => [
                'id' => $id,
                'name' => $users[$id]->name,
                'profile_image_url' => $users[$id]->profile_image_url,
                'followers_count' => $users[$id]->followers_count,
                'reason' => $reasons[$id]['text'],
            ])
            ->values();
    }

    // id ที่ไม่ต้องแนะนำ (ใช้เป็น key เพื่อเช็กเร็ว)
    private function excludedIds(User $user): array
    {
        $familyId = FamilyMember::where('user_id', $user->id)->value('family_id');

        return collect([$user->id])
            ->merge($familyId ? FamilyMember::where('family_id', $familyId)->pluck('user_id') : [])
            ->merge($user->following()->pluck('users.id'))
            ->merge(UserBlock::where('user_id', $user->id)->pluck('blocked_user_id'))
            ->merge(UserBlock::where('blocked_user_id', $user->id)->pluck('user_id'))
            ->mapWithKeys(fn ($id) => [(int) $id => true])
            ->all();
    }
}
