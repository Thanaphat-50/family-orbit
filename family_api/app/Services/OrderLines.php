<?php

namespace App\Services;

use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use App\Models\UserBlock;
use Illuminate\Support\Collection;

// =======================================================
// รายการสินค้าที่จะซื้อ (ตะกร้า / ซื้อเลย / สั่งซื้อ)
// อ่านราคาและสต็อกจากฐานข้อมูลทุกครั้ง ไม่เชื่อราคาที่แอปส่งมา
// problem = เหตุผลที่สั่งรายการนี้ไม่ได้ (null = สั่งได้)
// =======================================================

class OrderLines
{
    /**
     * @param  array<int, array{product_id: mixed, variant_id?: mixed, quantity?: mixed}>  $items
     * @return Collection<int, array{product: ?Product, variant: ?ProductVariant, quantity: int, unit_price: ?float, stock: int, problem: ?string}>
     */
    public function resolve(User $user, array $items): Collection
    {
        $ids = collect($items)->pluck('product_id')->map(fn ($id) => (int) $id)->unique();

        $products = Product::visibleInMarket()
            ->with(['shop', 'images', 'variants'])
            ->whereIn('id', $ids)
            ->get()
            ->keyBy('id');

        $blocked = UserBlock::where('user_id', $user->id)->pluck('blocked_user_id')
            ->merge(UserBlock::where('blocked_user_id', $user->id)->pluck('user_id'))
            ->map(fn ($id) => (int) $id);

        $max = (int) config('market.max_order_quantity');

        return collect($items)->map(function (array $item) use ($user, $products, $blocked, $max) {
            $product = $products->get((int) $item['product_id']);

            $quantity = max(1, (int) ($item['quantity'] ?? 1));

            $line = [
                'product' => $product,
                'variant' => null,
                'quantity' => $quantity,
                'unit_price' => null,
                'stock' => 0,
                'problem' => null,
            ];

            if (!$product || $blocked->contains((int) $product->shop->user_id)) {
                return [...$line, 'product' => null, 'problem' => 'สินค้านี้ไม่มีขายแล้ว'];
            }

            $variant = null;

            if ($product->hasVariants()) {
                $variant = $product->variants->firstWhere('id', (int) ($item['variant_id'] ?? 0));
            }

            $stock = $variant ? (int) $variant->stock : (int) $product->stock;

            $price = $variant
                ? $variant->effectivePrice()
                : ($product->price === null ? null : (float) $product->price);

            $problem = $product->orderBlockReason($user)
                ?? match (true) {
                    $product->hasVariants() && !$variant => 'กรุณาเลือกตัวเลือกสินค้า',
                    $price === null => 'สินค้านี้ให้สอบถามราคากับร้านก่อน',
                    $stock <= 0 => 'สินค้าหมดแล้ว',
                    $quantity > $stock => "เหลือ {$stock} ชิ้น",
                    $quantity > $max => "สั่งได้ครั้งละไม่เกิน {$max} ชิ้น",
                    default => null,
                };

            return [
                ...$line,
                'variant' => $variant,
                'unit_price' => $price,
                'stock' => $stock,
                'problem' => $problem,
            ];
        })->values();
    }

    // ข้อมูลรายการสำหรับแอป
    public static function payload(array $line): array
    {
        /** @var ?Product $product */
        $product = $line['product'];

        /** @var ?ProductVariant $variant */
        $variant = $line['variant'];

        return [
            'product_id' => $product?->id,
            'variant_id' => $variant?->id,
            'shop_id' => $product?->shop_id,
            'title' => $product?->title,
            'variant_name' => $variant?->name,
            'image_url' => $product?->images->first()?->url,
            'unit_price' => $line['unit_price'],
            'quantity' => $line['quantity'],
            'subtotal' => $line['unit_price'] === null ? null : round($line['unit_price'] * $line['quantity'], 2),
            'stock' => $line['stock'],
            'max_quantity' => min($line['stock'], (int) config('market.max_order_quantity')),
            'problem' => $line['problem'],
        ];
    }
}
