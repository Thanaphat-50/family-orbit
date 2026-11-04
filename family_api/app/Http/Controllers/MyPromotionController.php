<?php

namespace App\Http\Controllers;

use App\Models\Product;
use App\Models\ProductPromotion;
use App\Models\Shop;
use App\Models\ShopPromotion;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use Throwable;

// =======================================================
// ช่องแนะนำแบบชำระเงิน (ฝั่งผู้ขาย)
// - สินค้าแนะนำ: ช่องเล็ก ราคาถูก จำกัดต่อหมวด
// - ร้านแนะนำ: แบนเนอร์ใหญ่บนสุด ราคาแพงกว่า จำกัดรวมทั้งแอป
// เลือกแพ็กเกจ → โอนพร้อมเพย์ตาม QR → แนบสลิป → Admin ตรวจ → ขึ้นช่องแนะนำ
// ต่ออายุได้ (นับต่อจากวันหมดเดิม)
// =======================================================

class MyPromotionController extends Controller
{
    // =====================================================
    // GET /api/my-shop/products/{product}/promotion
    // =====================================================

    public function show(Request $request, Product $product)
    {
        $shop = $this->myShop($request);

        if (!$shop || (int) $product->shop_id !== (int) $shop->id) {
            return $this->notFound();
        }

        ProductPromotion::expireStale();

        $label = config('market.categories')[$product->category] ?? $product->category;

        $total = ProductPromotion::slotsPerCategory();
        $used = ProductPromotion::usedSlots($product->category, $product->id);

        return $this->info(
            ProductPromotion::class,
            featured: $product->isFeatured(),
            featuredUntil: $product->featured_until,
            used: $used,
            total: $total,
            openOrder: $product->promotions()->open()->latest()->first()?->setRelation('product', $product),
            history: $product->promotions()->latest()->limit(5)->get(),
            extra: [
                'category' => $product->category,
                'category_label' => $label,
                'slot_label' => "ช่องสินค้าแนะนำหมวด \"{$label}\"",
                'placement_label' => "ขึ้นในช่อง \"สินค้าแนะนำ\" ของหน้าร้านค้า และหมวด \"{$label}\"",
            ]
        );
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

        $plan = $this->validatePlan($request, ProductPromotion::class);

        if ($error = $this->cannotBuy($shop)) {
            return $error;
        }

        if ($product->status !== Product::STATUS_ACTIVE || $product->hidden_at !== null) {
            return $this->fail('สินค้านี้ถูกซ่อนอยู่ แสดงสินค้าก่อนจึงจะซื้อช่องแนะนำได้', 422);
        }

        ProductPromotion::expireStale();

        if ($open = $product->promotions()->open()->latest()->first()) {
            return $this->alreadyOpen($open->setRelation('product', $product));
        }

        $total = ProductPromotion::slotsPerCategory();

        if (!$product->isFeatured() && ProductPromotion::usedSlots($product->category, $product->id) >= $total) {
            $label = config('market.categories')[$product->category] ?? $product->category;

            return $this->fail("ช่องแนะนำหมวด \"{$label}\" เต็มแล้ว ({$total} ช่อง) ลองใหม่ภายหลัง", 409);
        }

        $order = ProductPromotion::create([
            'product_id' => $product->id,
            'user_id' => $request->user()->id,
            'plan' => $plan['key'],
            'days' => $plan['days'],
            'amount' => $plan['price'],
            'category' => $product->category,
            'status' => ProductPromotion::STATUS_AWAITING_PAYMENT,
        ]);

        return $this->created($order->setRelation('product', $product));
    }

    // =====================================================
    // GET /api/my-shop/promotion — ช่องร้านแนะนำของร้านฉัน
    // =====================================================

    public function showShop(Request $request)
    {
        $shop = $this->myShop($request);

        if (!$shop) {
            return $this->fail('คุณยังไม่มีร้าน', 404);
        }

        ShopPromotion::expireStale();

        return $this->info(
            ShopPromotion::class,
            featured: $shop->isFeatured(),
            featuredUntil: $shop->featured_until,
            used: ShopPromotion::usedSlots($shop->id),
            total: ShopPromotion::slots(),
            openOrder: $shop->promotions()->open()->latest()->first()?->setRelation('shop', $shop),
            history: $shop->promotions()->latest()->limit(5)->get(),
            extra: [
                'slot_label' => 'ช่องร้านแนะนำ',
                'placement_label' => 'ขึ้นในช่อง "ร้านแนะนำ" (แบนเนอร์ใหญ่) ด้านบนสุดของหน้าร้านค้า',
            ]
        );
    }

    // =====================================================
    // POST /api/my-shop/promotion {plan}
    // =====================================================

    public function storeShop(Request $request)
    {
        $shop = $this->myShop($request);

        if (!$shop) {
            return $this->fail('คุณยังไม่มีร้าน', 404);
        }

        $plan = $this->validatePlan($request, ShopPromotion::class);

        if ($error = $this->cannotBuy($shop)) {
            return $error;
        }

        ShopPromotion::expireStale();

        if ($open = $shop->promotions()->open()->latest()->first()) {
            return $this->alreadyOpen($open->setRelation('shop', $shop));
        }

        $total = ShopPromotion::slots();

        if (!$shop->isFeatured() && ShopPromotion::usedSlots($shop->id) >= $total) {
            return $this->fail("ช่องร้านแนะนำเต็มแล้ว ({$total} ช่อง) ลองใหม่ภายหลัง", 409);
        }

        $order = ShopPromotion::create([
            'shop_id' => $shop->id,
            'user_id' => $request->user()->id,
            'plan' => $plan['key'],
            'days' => $plan['days'],
            'amount' => $plan['price'],
            'status' => ShopPromotion::STATUS_AWAITING_PAYMENT,
        ]);

        return $this->created($order->setRelation('shop', $shop));
    }

    // =====================================================
    // GET /api/my-shop/promotions — รายการสินค้าแนะนำที่สั่งซื้อ
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
    // POST /api/my-shop/shop-promotions/{shopPromotion}/slip
    // แนบสลิปได้ตอนรอชำระ หรือเปลี่ยนสลิปตอนรอตรวจ
    // =====================================================

    public function uploadSlip(Request $request, ProductPromotion $promotion)
    {
        return $this->attachSlip($request, $promotion->load('product:id,title'));
    }

    public function uploadShopSlip(Request $request, ShopPromotion $shopPromotion)
    {
        return $this->attachSlip($request, $shopPromotion->load('shop:id,name'));
    }

    // =====================================================
    // POST /api/my-shop/promotions/{promotion}/cancel
    // POST /api/my-shop/shop-promotions/{shopPromotion}/cancel
    // =====================================================

    public function cancel(Request $request, ProductPromotion $promotion)
    {
        return $this->cancelOrder($request, $promotion->load('product:id,title'));
    }

    public function cancelShop(Request $request, ShopPromotion $shopPromotion)
    {
        return $this->cancelOrder($request, $shopPromotion->load('shop:id,name'));
    }

    // =====================================================
    // HELPERS (ProductPromotion / ShopPromotion ใช้ร่วมกัน)
    // =====================================================

    private function info(
        string $model,
        bool $featured,
        $featuredUntil,
        int $used,
        int $total,
        ?Model $openOrder,
        $history,
        array $extra
    ) {
        return response()->json([
            'status' => true,
            'payment_enabled' => $model::paymentEnabled(),
            'plans' => $model::plansPayload(),
            'slots' => [
                'total' => $total,
                'used' => $used,
                'available' => $featured || $used < $total,
            ],
            'featured_until' => $featuredUntil,
            'is_featured' => $featured,
            'open_order' => $openOrder?->toSellerPayload(),
            'history' => $history->map(fn (Model $promotion) => $promotion->toSellerPayload())->values(),
            ...$extra,
        ]);
    }

    // แพ็กเกจที่เลือก → ['key', 'days', 'price']
    private function validatePlan(Request $request, string $model): array
    {
        $plans = config($model::plansConfigKey());

        $data = $request->validate([
            'plan' => ['required', Rule::in(array_keys($plans))],
        ], [
            'plan.*' => 'กรุณาเลือกแพ็กเกจ',
        ]);

        return [
            'key' => $data['plan'],
            'days' => (int) $plans[$data['plan']]['days'],
            'price' => (int) $plans[$data['plan']]['price'],
        ];
    }

    private function cannotBuy(Shop $shop)
    {
        if (!$shop->isActive()) {
            return $this->fail('ร้านต้องเปิดขายอยู่ จึงจะซื้อช่องแนะนำได้', 422);
        }

        if (!ProductPromotion::paymentEnabled()) {
            return $this->fail('ยังไม่เปิดรับชำระเงินค่าช่องแนะนำ', 422);
        }

        return null;
    }

    private function alreadyOpen(Model $open)
    {
        return response()->json([
            'status' => false,
            'message' => $open->status === ProductPromotion::STATUS_PENDING_REVIEW
                ? 'มีสลิปรอตรวจอยู่แล้ว'
                : 'มีรายการรอชำระอยู่แล้ว',
            'order' => $open->toSellerPayload(),
        ], 409);
    }

    private function created(Model $order)
    {
        return response()->json([
            'status' => true,
            'message' => 'สร้างรายการแล้ว โอนตาม QR แล้วแนบสลิปภายใน '
                . config('market.promotion_payment_hours') . ' ชั่วโมง',
            'order' => $order->toSellerPayload(),
        ], 201);
    }

    private function attachSlip(Request $request, Model $promotion)
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
            $promotion->attachSlip($request->file('slip'));
        } catch (Throwable $e) {
            Log::error('Promotion slip upload failed', [
                'promotion' => $promotion::class . '#' . $promotion->id,
                'error' => $e->getMessage(),
            ]);

            return $this->fail('อัปโหลดสลิปไม่สำเร็จ กรุณาลองอีกครั้ง', 500);
        }

        return response()->json([
            'status' => true,
            'message' => 'ส่งสลิปแล้ว รอทีมงานตรวจสอบ',
            'order' => $promotion->toSellerPayload(),
        ]);
    }

    private function cancelOrder(Request $request, Model $promotion)
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
            'order' => $promotion->toSellerPayload(),
        ]);
    }

    private function myShop(Request $request): ?Shop
    {
        return Shop::where('user_id', $request->user()->id)->first();
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
