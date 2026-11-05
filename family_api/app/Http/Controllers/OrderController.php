<?php

namespace App\Http\Controllers;

use App\Models\Order;
use App\Models\OutOfStock;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use Throwable;

// =======================================================
// สั่งซื้อสินค้า (ผู้ซื้อ + ร้าน)
// - เงินโอนเข้าร้านโดยตรง แอปไม่ได้รับเงินแทน
// - ปุ่มที่กดได้มาจาก Order::actionsFor() (แอปแสดงตามนั้น)
// =======================================================

class OrderController extends Controller
{
    private const PAGE_SIZE = 20;

    // คำสั่งซื้อที่ยังไม่จ่ายค้างพร้อมกันได้ (กันจองสต็อกทิ้งไว้)
    private const MAX_UNPAID_PER_BUYER = 10;
    private const MAX_UNPAID_PER_SHOP = 3;

    // =====================================================
    // GET /api/orders/checkout?product_id=
    // ข้อมูลหน้าสั่งซื้อ: วิธีรับสินค้า วิธีจ่าย ค่าส่ง จำนวนที่สั่งได้
    // =====================================================

    public function checkout(Request $request)
    {
        $data = $request->validate(['product_id' => 'required|integer']);

        $user = $request->user();

        $product = $this->findOrderable($user, (int) $data['product_id']);

        if ($product instanceof JsonResponse) {
            return $product;
        }

        $shop = $product->shop;

        $fee = (float) ($product->shipping_fee ?? 0);

        $last = Order::where('buyer_id', $user->id)->latest('id')->first();

        return response()->json([
            'status' => true,
            'product' => [
                ...$product->only(['id', 'title', 'price', 'stock', 'shipping_fee']),
                'image_url' => $product->images->first()?->url,
            ],
            'shop' => [
                ...$shop->only(['id', 'name']),
                'logo_url' => $shop->logo_url,
            ],
            'max_quantity' => min((int) $product->stock, (int) config('market.max_order_quantity')),
            'delivery_methods' => collect($shop->orderDeliveryMethods())->map(fn (string $key) => [
                'key' => $key,
                'label' => config("market.delivery_methods.{$key}"),
                'shipping_fee' => in_array($key, config('market.shipping_fee_methods'), true) ? $fee : 0,
                'needs_address' => in_array($key, config('market.address_methods'), true),
                'payment_methods' => collect($shop->paymentMethodsFor($key))->map(fn (string $method) => [
                    'key' => $method,
                    'label' => config("market.payment_methods.{$method}.label"),
                    'transfer' => (bool) config("market.payment_methods.{$method}.transfer"),
                ])->values(),
            ])->values(),
            // กรอกให้ล่วงหน้าจากคำสั่งซื้อล่าสุด
            'recipient' => [
                'name' => $last?->recipient_name ?? $user->name,
                'phone' => $last?->recipient_phone ?? '',
                'address' => $last?->address ?? '',
            ],
        ]);
    }

    // =====================================================
    // POST /api/orders
    // =====================================================

    public function store(Request $request)
    {
        $needsAddress = in_array($request->input('delivery_method'), config('market.address_methods'), true);

        $data = $request->validate([
            'product_id' => 'required|integer',
            'quantity' => 'required|integer|min:1|max:' . config('market.max_order_quantity'),
            'delivery_method' => ['required', Rule::in(array_keys(config('market.delivery_methods')))],
            'payment_method' => ['required', Rule::in(array_keys(config('market.payment_methods')))],
            'recipient_name' => 'required|string|max:100',
            'recipient_phone' => ['required', 'string', 'regex:/^\+?[0-9][0-9\s\-]{7,18}$/'],
            'address' => [Rule::requiredIf($needsAddress), 'nullable', 'string', 'max:500'],
            'note' => 'nullable|string|max:500',
        ], [
            'quantity.*' => 'จำนวนต้องเป็น 1 – ' . config('market.max_order_quantity') . ' ชิ้น',
            'delivery_method.*' => 'กรุณาเลือกวิธีรับสินค้า',
            'payment_method.*' => 'กรุณาเลือกวิธีชำระเงิน',
            'recipient_name.required' => 'กรุณาใส่ชื่อผู้รับ',
            'recipient_name.max' => 'ชื่อผู้รับยาวได้ไม่เกิน 100 ตัวอักษร',
            'recipient_phone.required' => 'กรุณาใส่เบอร์โทรผู้รับ',
            'recipient_phone.regex' => 'เบอร์โทรไม่ถูกต้อง',
            'address.required' => 'กรุณาใส่ที่อยู่จัดส่ง',
            'address.max' => 'ที่อยู่ยาวได้ไม่เกิน 500 ตัวอักษร',
            'note.max' => 'หมายเหตุยาวได้ไม่เกิน 500 ตัวอักษร',
        ]);

        $user = $request->user();

        $product = $this->findOrderable($user, (int) $data['product_id']);

        if ($product instanceof JsonResponse) {
            return $product;
        }

        $shop = $product->shop;

        if (!in_array($data['delivery_method'], $shop->orderDeliveryMethods(), true)) {
            return $this->fail('ร้านไม่ได้เปิดวิธีรับสินค้านี้ กรุณาเลือกใหม่');
        }

        if (!in_array($data['payment_method'], $shop->paymentMethodsFor($data['delivery_method']), true)) {
            return $this->fail('วิธีชำระเงินนี้ใช้กับวิธีรับสินค้าที่เลือกไม่ได้');
        }

        $unpaid = Order::where('buyer_id', $user->id)->unpaidReservation();

        if ((clone $unpaid)->count() >= self::MAX_UNPAID_PER_BUYER
            || (clone $unpaid)->where('shop_id', $shop->id)->count() >= self::MAX_UNPAID_PER_SHOP) {
            return $this->fail('คุณมีคำสั่งซื้อที่ยังไม่ได้ชำระหลายรายการแล้ว ชำระหรือยกเลิกก่อนสั่งเพิ่ม', 429);
        }

        try {
            $order = Order::place($user, $product, $data);
        } catch (OutOfStock $e) {
            return $this->fail(
                $e->remaining > 0 ? "สินค้าเหลือ {$e->remaining} ชิ้น กรุณาลดจำนวน" : 'สินค้าหมดแล้ว',
                409
            );
        }

        return response()->json([
            'status' => true,
            'message' => $order->isTransfer()
                ? 'สั่งซื้อแล้ว โอนเงินแล้วแนบสลิปได้เลย'
                : 'สั่งซื้อแล้ว รอร้านจัดส่ง',
            'order' => $order->toPayload($user),
        ], 201);
    }

    // =====================================================
    // GET /api/orders?filter=open|completed|cancelled  (ที่ฉันซื้อ)
    // GET /api/my-shop/orders?filter=todo|open|completed|cancelled  (ลูกค้าของร้าน)
    // =====================================================

    public function index(Request $request)
    {
        $user = $request->user();

        return $this->list($request, Order::where('buyer_id', $user->id), $user);
    }

    public function shopIndex(Request $request)
    {
        $user = $request->user();

        $shop = Shop::where('user_id', $user->id)->first();

        if (!$shop) {
            return $this->fail('คุณยังไม่มีร้าน', 404);
        }

        return $this->list($request, Order::where('shop_id', $shop->id), $user, [
            'todo' => Order::where('shop_id', $shop->id)->whereIn('status', Order::SELLER_TODO_STATUSES)->count(),
        ]);
    }

    // =====================================================
    // GET /api/orders/{order}
    // =====================================================

    public function show(Request $request, Order $order)
    {
        $user = $request->user();

        Order::expireStale();

        $order->refresh();

        if (!$order->isBuyer($user) && !$order->isSeller($user)) {
            return $this->notFound();
        }

        return response()->json([
            'status' => true,
            'order' => $order->toPayload($user),
        ]);
    }

    // =====================================================
    // ร้าน: สลิปไม่ถูกต้อง (เงินไม่เข้า) / ส่งสินค้า
    // =====================================================

    public function rejectSlip(Request $request, Order $order)
    {
        $data = $request->validate(
            ['reason' => 'required|string|max:300'],
            ['reason.*' => 'กรุณาบอกเหตุผล (ไม่เกิน 300 ตัวอักษร)']
        );

        return $this->act(
            $request,
            $order,
            'reject_slip',
            'แจ้งผู้ซื้อให้แนบสลิปใหม่แล้ว',
            fn () => $order->rejectSlip(trim($data['reason']))
        );
    }

    public function ship(Request $request, Order $order)
    {
        $data = $request->validate([
            'tracking_number' => 'nullable|string|max:60',
            'seller_note' => 'nullable|string|max:500',
        ], [
            'tracking_number.*' => 'เลขพัสดุยาวได้ไม่เกิน 60 ตัวอักษร',
            'seller_note.*' => 'ข้อความยาวได้ไม่เกิน 500 ตัวอักษร',
        ]);

        return $this->act(
            $request,
            $order,
            'ship',
            'บันทึกการส่งสินค้าแล้ว',
            fn () => $order->ship(
                filled($data['tracking_number'] ?? null) ? trim($data['tracking_number']) : null,
                filled($data['seller_note'] ?? null) ? trim($data['seller_note']) : null
            )
        );
    }

    // =====================================================
    // ผู้ซื้อ: แนบสลิป / ได้รับสินค้าแล้ว
    // =====================================================

    public function uploadSlip(Request $request, Order $order)
    {
        $request->validate(
            ['slip' => 'required|image|mimes:jpg,jpeg,png,webp|max:6144'],
            ['slip.*' => 'สลิปต้องเป็นรูป JPG, PNG หรือ WEBP ไม่เกิน 6 MB']
        );

        return $this->act($request, $order, 'pay', 'ส่งสลิปแล้ว รอร้านจัดส่ง', function () use ($request, $order) {
            try {
                $order->attachSlip($request->file('slip'));
            } catch (Throwable $e) {
                Log::error('Order slip upload failed', ['order_id' => $order->id, 'error' => $e->getMessage()]);

                return $this->fail('อัปโหลดสลิปไม่สำเร็จ กรุณาลองอีกครั้ง', 500);
            }

            return null;
        });
    }

    public function received(Request $request, Order $order)
    {
        return $this->act($request, $order, 'received', 'ขอบคุณที่ยืนยัน คำสั่งซื้อสำเร็จแล้ว', fn () => $order->complete());
    }

    // =====================================================
    // POST /api/orders/{order}/cancel  (ผู้ซื้อ หรือ ร้าน)
    // ร้านต้องบอกเหตุผล
    // =====================================================

    public function cancel(Request $request, Order $order)
    {
        $user = $request->user();

        if (!$order->isBuyer($user) && !$order->isSeller($user)) {
            return $this->notFound();
        }

        $bySeller = !$order->isBuyer($user);

        $data = $request->validate(
            ['reason' => [$bySeller ? 'required' : 'nullable', 'string', 'max:300']],
            ['reason.*' => 'กรุณาบอกเหตุผลที่ยกเลิก (ไม่เกิน 300 ตัวอักษร)']
        );

        $reason = filled($data['reason'] ?? null) ? trim($data['reason']) : null;

        return $this->act(
            $request,
            $order,
            'cancel',
            'ยกเลิกคำสั่งซื้อแล้ว',
            fn () => $order->cancel($bySeller ? Order::BY_SELLER : Order::BY_BUYER, $reason)
        );
    }

    // =====================================================
    // HELPERS
    // =====================================================

    // ตรวจว่าทำรายการนี้ได้ แล้วทำ → ส่งคำสั่งซื้อล่าสุดกลับ
    // work คืน JsonResponse เมื่อไม่สำเร็จ
    private function act(Request $request, Order $order, string $action, string $message, callable $work)
    {
        $user = $request->user();

        Order::expireStale();

        $order->refresh();

        if (!$order->isBuyer($user) && !$order->isSeller($user)) {
            return $this->notFound();
        }

        if (!in_array($action, $order->actionsFor($user), true)) {
            return response()->json([
                'status' => false,
                'message' => 'คำสั่งซื้อนี้เปลี่ยนสถานะไปแล้ว ทำรายการนี้ไม่ได้',
                'order' => $order->toPayload($user),
            ], 409);
        }

        $failed = $work();

        if ($failed instanceof JsonResponse) {
            return $failed;
        }

        return response()->json([
            'status' => true,
            'message' => $message,
            'order' => $order->refresh()->toPayload($user),
        ]);
    }

    private function list(Request $request, $query, User $user, array $extra = [])
    {
        $data = $request->validate([
            'filter' => ['nullable', Rule::in(['todo', 'open', 'completed', 'cancelled'])],
        ]);

        Order::expireStale();

        $paginator = $query
            ->when($data['filter'] ?? null, fn ($orders, string $filter) => match ($filter) {
                'todo' => $orders->whereIn('status', Order::SELLER_TODO_STATUSES),
                'open' => $orders->whereIn('status', Order::OPEN_STATUSES),
                default => $orders->where('status', $filter),
            })
            ->with(['shop', 'buyer', 'product.images'])
            ->latest('id')
            ->simplePaginate(self::PAGE_SIZE);

        return response()->json([
            'status' => true,
            'orders' => collect($paginator->items())
                ->map(fn (Order $order) => $order->toPayload($user))
                ->values(),
            'page' => $paginator->currentPage(),
            'has_more' => $paginator->hasMorePages(),
            ...$extra,
        ]);
    }

    // สินค้าที่ผู้ใช้คนนี้สั่งได้ (ไม่ได้ → คืนข้อความที่แอปแสดงได้เลย)
    private function findOrderable(User $user, int $productId): Product|JsonResponse
    {
        $product = Product::visibleInMarket()->with(['shop', 'images'])->find($productId);

        if (!$product || $this->blockedBetween($user, (int) $product->shop->user_id)) {
            return $this->fail('ไม่พบสินค้านี้ หรือสินค้าถูกซ่อนแล้ว', 404);
        }

        $reason = $product->orderBlockReason($user);

        return $reason === null ? $product : $this->fail($reason);
    }

    // บล็อกกันฝั่งใดฝั่งหนึ่ง → สั่งซื้อกันไม่ได้
    private function blockedBetween(User $user, int $otherId): bool
    {
        return $user->blockedUsers()->where('users.id', $otherId)->exists()
            || User::find($otherId)?->blockedUsers()->where('users.id', $user->id)->exists();
    }

    private function fail(string $message, int $status = 422)
    {
        return response()->json([
            'status' => false,
            'message' => $message,
        ], $status);
    }

    private function notFound()
    {
        return $this->fail('ไม่พบคำสั่งซื้อนี้', 404);
    }
}
