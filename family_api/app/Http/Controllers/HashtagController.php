<?php

namespace App\Http\Controllers;

use App\Models\Hashtag;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

// =======================================================
// แฮชแท็กยอดนิยม: ใช้มากที่สุดในโพสต์ชุมชน 30 วันล่าสุด
// (ไม่นับโพสต์ที่ถูกซ่อน) เก็บผลไว้ 10 นาที
// =======================================================

class HashtagController extends Controller
{
    private const LIMIT = 15;

    // GET /api/hashtags/popular
    public function popular()
    {
        $tags = Cache::remember('hashtags:popular', now()->addMinutes(10), function () {
            return Hashtag::query()
                ->join('hashtag_post', 'hashtag_post.hashtag_id', '=', 'hashtags.id')
                ->join('posts', 'posts.id', '=', 'hashtag_post.post_id')
                ->where('posts.visibility', 'community')
                ->whereNull('posts.hidden_at')
                ->where('posts.created_at', '>=', now()->subDays(30))
                ->groupBy('hashtags.id', 'hashtags.name')
                ->orderByDesc('posts_count')
                ->orderBy('hashtags.name')
                ->limit(self::LIMIT)
                ->get(['hashtags.name', DB::raw('count(*) as posts_count')])
                ->map(fn ($tag) => [
                    'name' => $tag->name,
                    'posts_count' => (int) $tag->posts_count,
                ])
                ->all();
        });

        return response()->json([
            'status' => true,
            'hashtags' => $tags,
        ]);
    }
}
