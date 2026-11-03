<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\Shop;
use App\Models\ShopReview;
use Illuminate\Http\Request;

// =======================================================
// รีวิวร้าน 1–5 ดาว
// - 1 คนต่อ 1 ร้าน (ส่งซ้ำ = แก้ไขรีวิวเดิม)
// - รีวิวร้านตัวเองไม่ได้ / Admin ซ่อนรีวิวได้
// =======================================================

class ShopReviewController extends Controller
{
    // =====================================================
    // GET /api/market/shops/{shop}/reviews?page=
    // =====================================================

    public function index(Request $request, Shop $shop)
    {
        $user = $request->user();

        $isMine = (int) $shop->user_id === (int) $user->id;

        if (!$isMine && $this->unavailable($request, $shop)) {
            return $this->notFound();
        }

        $blockedIds = $user->blockedUsers()->pluck('users.id');

        $page = ShopReview::where('shop_id', $shop->id)
            ->visible()
            ->whereNotIn('user_id', $blockedIds)
            ->with('user')
            ->latest()
            ->paginate(20);

        $mine = ShopReview::where('shop_id', $shop->id)
            ->where('user_id', $user->id)
            ->with('user')
            ->first();

        return response()->json([
            'status' => true,
            'reviews' => collect($page->items())
                ->map(fn (ShopReview $review) => $review->toPayload($user->id))
                ->values(),
            'has_more' => $page->hasMorePages(),
            'summary' => ShopReview::summaryFor($shop->id),
            'my_review' => $mine?->toPayload($user->id),
            'can_review' => !$isMine,
        ]);
    }

    // =====================================================
    // POST /api/market/shops/{shop}/reviews {rating, comment}
    // =====================================================

    public function store(Request $request, Shop $shop)
    {
        $user = $request->user();

        if ((int) $shop->user_id === (int) $user->id) {
            return response()->json([
                'status' => false,
                'message' => 'รีวิวร้านของตัวเองไม่ได้',
            ], 422);
        }

        if ($this->unavailable($request, $shop)) {
            return $this->notFound();
        }

        $data = $request->validate([
            'rating' => 'required|integer|min:1|max:5',
            'comment' => 'nullable|string|max:' . ShopReview::MAX_COMMENT,
        ], [
            'rating.*' => 'กรุณาให้คะแนน 1–5 ดาว',
            'comment.max' => 'รีวิวยาวได้ไม่เกิน ' . ShopReview::MAX_COMMENT . ' ตัวอักษร',
        ]);

        $comment = trim((string) ($data['comment'] ?? ''));

        $review = ShopReview::updateOrCreate(
            ['shop_id' => $shop->id, 'user_id' => $user->id],
            ['rating' => $data['rating'], 'comment' => $comment !== '' ? $comment : null]
        );

        // แจ้งเจ้าของร้านเฉพาะรีวิวใหม่ (แก้ไขรีวิวไม่แจ้งซ้ำ)
        if ($review->wasRecentlyCreated) {
            AppNotification::create([
                'user_id' => $shop->user_id,
                'family_id' => null,
                'type' => 'shop_review',
                'title' => 'มีรีวิวร้านใหม่',
                'message' => $user->name . ' ให้ ' . $review->rating . ' ดาว กับร้าน "' . $shop->name . '"',
                'data' => [
                    'shop_id' => $shop->id,
                    'review_id' => $review->id,
                ],
                'is_read' => false,
            ]);
        }

        return response()->json([
            'status' => true,
            'message' => $review->wasRecentlyCreated ? 'ขอบคุณสำหรับรีวิว' : 'แก้ไขรีวิวแล้ว',
            'review' => $review->load('user')->toPayload($user->id),
            'summary' => ShopReview::summaryFor($shop->id),
        ], $review->wasRecentlyCreated ? 201 : 200);
    }

    // =====================================================
    // DELETE /api/market/shops/{shop}/reviews
    // =====================================================

    public function destroy(Request $request, Shop $shop)
    {
        ShopReview::where('shop_id', $shop->id)
            ->where('user_id', $request->user()->id)
            ->delete();

        return response()->json([
            'status' => true,
            'message' => 'ลบรีวิวแล้ว',
            'summary' => ShopReview::summaryFor($shop->id),
        ]);
    }

    // ร้านปิดอยู่ หรือมีการบล็อกกัน
    private function unavailable(Request $request, Shop $shop): bool
    {
        return !$shop->isActive()
            || $request->user()->blockedUsers()->where('users.id', $shop->user_id)->exists();
    }

    private function notFound()
    {
        return response()->json([
            'status' => false,
            'message' => 'ไม่พบร้านนี้ หรือร้านปิดอยู่',
        ], 404);
    }
}
