<?php

namespace App\Http\Controllers;

use App\Models\Product;
use App\Models\ProductPromotion;
use App\Models\Shop;
use App\Support\MediaStorage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use RuntimeException;
use Throwable;

// =======================================================
// ช่องแนะนำสินค้า (ฝั่งผู้ขาย)
// เลือกแพ็กเกจ → โอนพร้อมเพย์ตาม QR → แนบสลิป → Admin ตรวจ → ขึ้นช่องแนะนำ
// ช่องจำกัดต่อหมวด / ต่ออายุได้ (นับต่อจากวันหมดเดิม)
// =======================================================

class MyPromotionController extends Controller
{
    // =====================================================
    // GET /api/my-shop/products/{product}/promotion
    // แพ็กเกจ + ช่องว่างในหมวด + คำสั่งซื้อที่ค้างอยู่
    // =====================================================

    public function show(Request $request, Product $product)
    {
        $shop = $this->myShop($request);

        if (!$shop || (int) $product->shop_id !== (int) $shop->id) {
            return $this->notFound();
        }

        ProductPromotion::expireStale();

        $total = ProductPromotion::slotsPerCategory();
        $used = ProductPromotion::usedSlots($product->category, $product->id);

        return response()->json([
            'status' => true,
            'payment_enabled' => ProductPromotion::paymentEnabled(),
            'plans' => ProductPromotion::plansPayload(),
            'category' => $product->category,
            'category_label' => config('market.categories')[$product->category] ?? $product->category,
            'slots' => [
                'total' => $total,
                'used' => $used,
                'available' => $product->isFeatured() || $used < $total,
            ],
            'featured_until' => $product->featured_until,
            'is_featured' => $product->isFeatured(),
            'open_order' => $this->openOrder($product)?->toSellerPayload(),
            'history' => $product->promotions()->latest()->limit(5)->get()
                ->map(fn (ProductPromotion $promotion) => $promotion->toSellerPayload())
                ->values(),
        ]);
    }

    // =====================================================
    // POST /api/my-shop/products/{product}/promotion {plan}
    // =====================================================

    public function store(Request $request, Product $product)
    {
        $shop = $this->myShop($request);

        if (!$shop || (int) $product->shop_id !== (int) $shop->id) {
            return $this->notFound();
        }

        $data = $request->validate([
            'plan' => ['required', Rule::in(array_keys(config('market.promotion_plans')))],
        ], [
            'plan.*' => 'กรุณาเลือกแพ็กเกจ',
        ]);

        if (!$shop->isActive()) {
            return $this->fail('ร้านต้องได้รับอนุมัติก่อน จึงจะซื้อช่องแนะนำได้', 422);
        }

        if ($product->status !== Product::STATUS_ACTIVE || $product->hidden_at !== null) {
            return $this->fail('สินค้านี้ถูกซ่อนอยู่ แสดงสินค้าก่อนจึงจะซื้อช่องแนะนำได้', 422);
        }

        if (!ProductPromotion::paymentEnabled()) {
            return $this->fail('ยังไม่เปิดรับชำระเงินค่าช่องแนะนำ', 422);
        }

        ProductPromotion::expireStale();

        if ($open = $this->openOrder($product)) {
            return response()->json([
                'status' => false,
                'message' => $open->status === ProductPromotion::STATUS_PENDING_REVIEW
                    ? 'สินค้านี้มีสลิปรอตรวจอยู่แล้ว'
                    : 'สินค้านี้มีรายการรอชำระอยู่แล้ว',
                'order' => $open->toSellerPayload(),
            ], 409);
        }

        $total = ProductPromotion::slotsPerCategory();

        if (!$product->isFeatured() && ProductPromotion::usedSlots($product->category, $product->id) >= $total) {
            $label = config('market.categories')[$product->category] ?? $product->category;

            return $this->fail("ช่องแนะนำหมวด \"{$label}\" เต็มแล้ว ({$total} ช่อง) ลองใหม่ภายหลัง", 409);
        }

        $plan = config('market.promotion_plans')[$data['plan']];

        $order = ProductPromotion::create([
            'product_id' => $product->id,
            'user_id' => $request->user()->id,
            'plan' => $data['plan'],
            'days' => (int) $plan['days'],
            'amount' => (int) $plan['price'],
            'category' => $product->category,
            'status' => ProductPromotion::STATUS_AWAITING_PAYMENT,
        ]);

        return response()->json([
            'status' => true,
            'message' => 'สร้างรายการแล้ว โอนตาม QR แล้วแนบสลิปภายใน '
                . config('market.promotion_payment_hours') . ' ชั่วโมง',
            'order' => $order->setRelation('product', $product)->toSellerPayload(),
        ], 201);
    }

    // =====================================================
    // GET /api/my-shop/promotions
    // =====================================================

    public function index(Request $request)
    {
        ProductPromotion::expireStale();

        $orders = ProductPromotion::where('user_id', $request->user()->id)
            ->with('product:id,title')
            ->latest()
            ->limit(30)
            ->get();

        return response()->json([
            'status' => true,
            'orders' => $orders->map(fn (ProductPromotion $promotion) => $promotion->toSellerPayload())->values(),
        ]);
    }

    // =====================================================
    // POST /api/my-shop/promotions/{promotion}/slip (multipart slip)
    // แนบสลิปได้ตอนรอชำระ หรือเปลี่ยนสลิปตอนรอตรวจ
    // =====================================================

    public function uploadSlip(Request $request, ProductPromotion $promotion)
    {
        if ((int) $promotion->user_id !== (int) $request->user()->id) {
            return $this->orderNotFound();
        }

        if ($promotion->isExpired()) {
            $promotion->forceFill(['status' => ProductPromotion::STATUS_CANCELLED])->save();

            return $this->fail('หมดเวลาแนบสลิปแล้ว กรุณาสั่งซื้อใหม่', 422);
        }

        if (!in_array($promotion->status, [ProductPromotion::STATUS_AWAITING_PAYMENT, ProductPromotion::STATUS_PENDING_REVIEW], true)) {
            return $this->fail('รายการนี้แนบสลิปไม่ได้แล้ว', 422);
        }

        $request->validate([
            'slip' => 'required|image|mimes:jpg,jpeg,png,webp|max:5120',
        ], [
            'slip.*' => 'สลิปต้องเป็นรูป JPG, PNG หรือ WEBP ไม่เกิน 5 MB',
        ]);

        try {
            $path = $request->file('slip')->store('promotion_slips/' . $promotion->user_id, MediaStorage::disk())
                ?: throw new RuntimeException('Could not store the slip.');
        } catch (Throwable $e) {
            Log::error('Promotion slip upload failed', [
                'promotion_id' => $promotion->id,
                'error' => $e->getMessage(),
            ]);

            return $this->fail('อัปโหลดสลิปไม่สำเร็จ กรุณาลองอีกครั้ง', 500);
        }

        $old = $promotion->slip_path;

        $promotion->forceFill([
            'slip_path' => $path,
            'slip_uploaded_at' => now(),
            'status' => ProductPromotion::STATUS_PENDING_REVIEW,
        ])->save();

        MediaStorage::delete([$old]);

        return response()->json([
            'status' => true,
            'message' => 'ส่งสลิปแล้ว รอทีมงานตรวจสอบ',
            'order' => $promotion->load('product:id,title')->toSellerPayload(),
        ]);
    }

    // =====================================================
    // POST /api/my-shop/promotions/{promotion}/cancel
    // =====================================================

    public function cancel(Request $request, ProductPromotion $promotion)
    {
        if ((int) $promotion->user_id !== (int) $request->user()->id) {
            return $this->orderNotFound();
        }

        if ($promotion->status !== ProductPromotion::STATUS_AWAITING_PAYMENT) {
            return $this->fail('ยกเลิกได้เฉพาะรายการที่ยังไม่ได้แนบสลิป', 422);
        }

        $promotion->forceFill(['status' => ProductPromotion::STATUS_CANCELLED])->save();

        return response()->json([
            'status' => true,
            'message' => 'ยกเลิกรายการแล้ว',
            'order' => $promotion->load('product:id,title')->toSellerPayload(),
        ]);
    }

    // =====================================================
    // HELPERS
    // =====================================================

    private function myShop(Request $request): ?Shop
    {
        return Shop::where('user_id', $request->user()->id)->first();
    }

    // รายการที่ยังไม่จบ: รอชำระ (ยังไม่หมดเวลา) / รอตรวจสลิป
    private function openOrder(Product $product): ?ProductPromotion
    {
        return $product->promotions()
            ->where(fn ($query) => $query
                ->where('status', ProductPromotion::STATUS_PENDING_REVIEW)
                ->orWhere(fn ($awaiting) => $awaiting->awaitingInTime()))
            ->latest()
            ->first()
            ?->setRelation('product', $product);
    }

    private function fail(string $message, int $status)
    {
        return response()->json([
            'status' => false,
            'message' => $message,
        ], $status);
    }

    private function notFound()
    {
        return $this->fail('ไม่พบสินค้านี้ในร้านของคุณ', 404);
    }

    private function orderNotFound()
    {
        return $this->fail('ไม่พบรายการนี้', 404);
    }
}
