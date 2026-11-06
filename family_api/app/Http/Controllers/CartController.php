<?php

namespace App\Http\Controllers;

use App\Models\CartItem;
use App\Models\Product;
use App\Services\OrderLines;
use Illuminate\Http\Request;

// =======================================================
// ตะกร้าสินค้า
// - เก็บแค่สินค้า/ตัวเลือก/จำนวน ราคาและสต็อกอ่านใหม่ทุกครั้งที่เปิด
// - สั่งซื้อแล้วเอาออกจากตะกร้าเอง (OrderController)
// =======================================================

class CartController extends Controller
{
    private const MAX_ITEMS = 50;

    // =====================================================
    // GET /api/cart → แยกตามร้าน + รายการที่สั่งไม่ได้แล้ว (problem)
    // =====================================================

    public function index(Request $request)
    {
        $user = $request->user();

        $items = CartItem::where('user_id', $user->id)->latest('id')->get();

        $lines = app(OrderLines::class)->resolve($user, $items->map(fn (CartItem $item) => [
            'product_id' => $item->product_id,
            'variant_id' => $item->variant_id,
            'quantity' => $item->quantity,
        ])->all());

        $rows = $items->values()->map(fn (CartItem $item, int $index) => [
            'id' => $item->id,
            ...OrderLines::payload($lines[$index]),
            // ร้านปิด/สินค้าถูกซ่อน → ยังแสดงชื่อเดิมให้ลบออกได้
            'title' => $lines[$index]['product']?->title ?? $item->product?->title,
            'shop' => $lines[$index]['product']?->shop?->only(['id', 'name'])
                ?? $item->product?->shop?->only(['id', 'name']),
        ]);

        return response()->json([
            'status' => true,
            'items' => $rows->values(),
            'count' => $items->sum('quantity'),
        ]);
    }

    public function count(Request $request)
    {
        return response()->json([
            'status' => true,
            'count' => (int) CartItem::where('user_id', $request->user()->id)->sum('quantity'),
        ]);
    }

    // =====================================================
    // POST /api/cart {product_id, variant_id, quantity} → เพิ่ม (มีอยู่แล้ว = บวกจำนวน)
    // =====================================================

    public function store(Request $request)
    {
        $max = (int) config('market.max_order_quantity');

        $data = $request->validate([
            'product_id' => 'required|integer',
            'variant_id' => 'nullable|integer',
            'quantity' => "nullable|integer|min:1|max:{$max}",
        ]);

        $user = $request->user();

        $existing = CartItem::where('user_id', $user->id)
            ->where('product_id', $data['product_id'])
            ->where('variant_id', $data['variant_id'] ?? null)
            ->first();

        $quantity = ($existing?->quantity ?? 0) + (int) ($data['quantity'] ?? 1);

        $line = app(OrderLines::class)->resolve($user, [[
            'product_id' => $data['product_id'],
            'variant_id' => $data['variant_id'] ?? null,
            'quantity' => $quantity,
        ]])->first();

        // เพิ่มเกินสต็อก/เกินจำนวนสูงสุด → ใส่เท่าที่สั่งได้
        if ($line['product'] && $line['stock'] > 0 && $quantity > min($line['stock'], $max)
            && (str_starts_with($line['problem'] ?? '', 'เหลือ ') || str_starts_with($line['problem'] ?? '', 'สั่งได้ครั้งละ'))) {
            $quantity = min($line['stock'], $max);

            $line['problem'] = null;
        }

        if ($line['problem'] !== null) {
            return response()->json([
                'status' => false,
                'message' => $line['problem'],
            ], 422);
        }

        if (!$existing && CartItem::where('user_id', $user->id)->count() >= self::MAX_ITEMS) {
            return response()->json([
                'status' => false,
                'message' => 'ตะกร้าเต็มแล้ว (ไม่เกิน ' . self::MAX_ITEMS . ' รายการ)',
            ], 422);
        }

        $item = $existing ?? new CartItem([
            'user_id' => $user->id,
            'product_id' => $line['product']->id,
            'variant_id' => $line['variant']?->id,
        ]);

        $item->quantity = min($quantity, $max);
        $item->save();

        return response()->json([
            'status' => true,
            'message' => 'เพิ่มลงตะกร้าแล้ว',
            'count' => (int) CartItem::where('user_id', $user->id)->sum('quantity'),
        ], 201);
    }

    // =====================================================
    // PATCH /api/cart/{cartItem} {quantity}
    // DELETE /api/cart/{cartItem}
    // =====================================================

    public function update(Request $request, CartItem $cartItem)
    {
        $max = (int) config('market.max_order_quantity');

        if ((int) $cartItem->user_id !== (int) $request->user()->id) {
            return $this->notFound();
        }

        $data = $request->validate(
            ['quantity' => "required|integer|min:1|max:{$max}"],
            ['quantity.*' => "จำนวนต้องเป็น 1 – {$max} ชิ้น"]
        );

        $cartItem->update(['quantity' => $data['quantity']]);

        return response()->json(['status' => true]);
    }

    public function destroy(Request $request, CartItem $cartItem)
    {
        if ((int) $cartItem->user_id !== (int) $request->user()->id) {
            return $this->notFound();
        }

        $cartItem->delete();

        return response()->json([
            'status' => true,
            'message' => 'เอาออกจากตะกร้าแล้ว',
        ]);
    }

    private function notFound()
    {
        return response()->json([
            'status' => false,
            'message' => 'ไม่พบสินค้านี้ในตะกร้า',
        ], 404);
    }
}
