<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\MarketFlag;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

// =======================================================
// ตรวจสินค้าต้องห้ามอัตโนมัติ (ร้านเปิดขายได้ทันที ไม่ต้องรออนุมัติ)
// - เทียบชื่อ/รายละเอียดกับคำใน config('market.prohibited')
// - ไม่สนช่องว่าง เครื่องหมาย ตัวพิมพ์ (กันเขียนแยกเลี่ยงคำ)
// - พบ → ซ่อนสินค้า / ปิดร้านทันที + บันทึก MarketFlag + แจ้งผู้ดูแลทุกคนและเจ้าของร้าน
//   (ผู้ดูแลกด "ไม่ผิดกฎ" → แสดงคืน)
// - คำเดิมที่ผู้ดูแลตรวจแล้ว ไม่แจ้งซ้ำ
// =======================================================

class MarketScreening
{
    // ข้อความ → ['categories' => [...], 'terms' => [...]] / ไม่พบ → null
    public function match(?string ...$texts): ?array
    {
        $text = $this->normalize(implode(' ', array_filter($texts)));

        foreach (config('market.allow_phrases', []) as $phrase) {
            $text = str_replace($this->normalize($phrase), ' ', $text);
        }

        $categories = [];
        $terms = [];

        foreach (config('market.prohibited', []) as $key => $group) {
            foreach ($group['terms'] as $term) {
                $needle = $this->normalize($term);

                if ($needle !== '' && str_contains($text, $needle)) {
                    $categories[$key] = true;
                    $terms[$term] = true;
                }
            }
        }

        if ($terms === []) {
            return null;
        }

        return [
            'categories' => array_keys($categories),
            'terms' => array_keys($terms),
        ];
    }

    public function screenProduct(Product $product): ?MarketFlag
    {
        $match = $this->match($product->title, $product->description);

        return $match
            ? $this->record($product, (int) $product->shop_id, $match, $product->title . ' ' . $product->description)
            : null;
    }

    public function screenShop(Shop $shop): ?MarketFlag
    {
        $match = $this->match($shop->name, $shop->description);

        return $match
            ? $this->record($shop, (int) $shop->id, $match, $shop->name . ' ' . $shop->description)
            : null;
    }

    // ตรวจทุกร้านและทุกสินค้า (ใช้ตอนเปิดระบบครั้งแรก) → จำนวนรายการที่พบ
    public function screenAll(): int
    {
        $found = 0;

        Shop::query()->each(function (Shop $shop) use (&$found) {
            $found += $this->screenShop($shop) ? 1 : 0;
        });

        Product::query()->each(function (Product $product) use (&$found) {
            $found += $this->screenProduct($product) ? 1 : 0;
        });

        return $found;
    }

    private function record(Model $item, int $shopId, array $match, string $excerpt): ?MarketFlag
    {
        $terms = $match['terms'];
        sort($terms);

        $fingerprint = hash('sha256', implode('|', $terms));

        $existing = MarketFlag::where('flaggable_type', $item::class)
            ->where('flaggable_id', $item->getKey())
            ->latest('id')
            ->first();

        // คำเดิม: ยังรอตรวจอยู่ หรือผู้ดูแลตรวจแล้ว → ไม่แจ้งซ้ำ
        if ($existing && $existing->fingerprint === $fingerprint) {
            return null;
        }

        $values = [
            'shop_id' => $shopId,
            'categories' => $match['categories'],
            'terms' => $match['terms'],
            'fingerprint' => $fingerprint,
            'excerpt' => Str::limit(trim(preg_replace('/\s+/u', ' ', $excerpt)), 290),
            'status' => MarketFlag::STATUS_OPEN,
            'reviewed_by' => null,
            'reviewed_at' => null,
        ];

        // ยังรอตรวจแต่คำเปลี่ยน → อัปเดตรายการเดิม / ไม่งั้นสร้างรายการใหม่
        $flag = $existing && $existing->status === MarketFlag::STATUS_OPEN
            ? tap($existing)->update($values)
            : MarketFlag::create([
                'flaggable_type' => $item::class,
                'flaggable_id' => $item->getKey(),
                ...$values,
            ]);

        $this->autoHide($flag, $item);

        $this->notifyAdmins($flag, $item);

        return $flag;
    }

    // ซ่อนสินค้า / ปิดร้านไว้ก่อน จนกว่าผู้ดูแลจะตรวจ + แจ้งเจ้าของร้าน
    public function autoHide(MarketFlag $flag, Model $item): void
    {
        if ($item instanceof Product && $item->hidden_at === null) {
            $item->forceFill(['hidden_at' => now()])->save();

            AppNotification::create([
                'user_id' => $item->shop->user_id,
                'family_id' => null,
                'type' => 'shop_status',
                'title' => 'สินค้าถูกซ่อนชั่วคราว',
                'message' => '"' . $item->title . '" มีคำที่อาจผิดกฎ (' . $flag->categoryLabels()
                    . ') ทีมงานจะตรวจสอบ ถ้าไม่ผิดกฎจะแสดงตามปกติ',
                'data' => ['shop_id' => $item->shop_id, 'product_id' => $item->id],
                'is_read' => false,
            ]);

            $flag->forceFill(['auto_hidden' => true])->save();
        }

        if ($item instanceof Shop && $item->status === Shop::STATUS_ACTIVE) {
            $item->suspend(Shop::AUTO_SCREEN_REASON);

            $flag->forceFill(['auto_hidden' => true])->save();
        }
    }

    private function notifyAdmins(MarketFlag $flag, Model $item): void
    {
        $isProduct = $item instanceof Product;

        $name = $isProduct ? $item->title : $item->name;

        $shopName = $isProduct ? $item->shop?->name : $item->name;

        foreach (User::where('is_admin', true)->pluck('id') as $adminId) {
            AppNotification::create([
                'user_id' => $adminId,
                'family_id' => null,
                'type' => 'market_flag',
                'title' => $isProduct ? 'ตรวจพบสินค้าที่อาจผิดกฎหมาย' : 'ตรวจพบร้านที่อาจผิดกฎหมาย',
                'message' => '"' . $name . '"'
                    . ($isProduct && $shopName ? ' (ร้าน ' . $shopName . ')' : '')
                    . ' เข้าข่าย ' . $flag->categoryLabels()
                    . ' · คำที่พบ: ' . implode(', ', $flag->terms)
                    . ($flag->auto_hidden ? ' · ' . ($isProduct ? 'ซ่อนสินค้า' : 'ปิดร้าน') . 'ไว้แล้ว รอคุณตรวจ' : ''),
                'data' => [
                    'flag_id' => $flag->id,
                    'shop_id' => $flag->shop_id,
                    'product_id' => $isProduct ? $item->getKey() : null,
                ],
                'is_read' => false,
            ]);
        }
    }

    // ตัวพิมพ์เล็ก + ตัดช่องว่าง เครื่องหมาย ตัวอักษรล่องหน
    private function normalize(string $text): string
    {
        $text = mb_strtolower($text);

        return preg_replace('/[\s\p{P}\p{S}\x{200B}-\x{200D}\x{2060}\x{FEFF}]+/u', '', $text) ?? $text;
    }
}
