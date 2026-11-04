<?php

namespace App\Models;

use App\Models\Concerns\PromotionPayment;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

// =======================================================
// คำสั่งซื้อช่อง "สินค้าแนะนำ" (ช่องเล็ก ราคาถูกกว่า)
// ช่องจำกัดต่อหมวด / สถานะและการชำระเงินดู Concerns\PromotionPayment
// =======================================================

class ProductPromotion extends Model
{
    use PromotionPayment;

    protected $fillable = [
        'product_id',
        'user_id',
        'plan',
        'days',
        'amount',
        'category',
        'status',
        'slip_path',
        'slip_uploaded_at',
        'reviewed_by',
        'reviewed_at',
        'reject_reason',
        'starts_at',
        'ends_at',
    ];

    protected $hidden = [
        'slip_path',
        'reviewed_by',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'days' => 'integer',
        'slip_uploaded_at' => 'datetime',
        'reviewed_at' => 'datetime',
        'starts_at' => 'datetime',
        'ends_at' => 'datetime',
    ];

    public static function plansConfigKey(): string
    {
        return 'market.promotion_plans';
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public static function slotsPerCategory(): int
    {
        return (int) config('market.featured_slots_per_category');
    }

    // จำนวนช่องที่ใช้อยู่ในหมวด (นับเป็นสินค้า): แนะนำอยู่ + มีคำสั่งซื้อรอตรวจ/รอชำระ (จองช่องไว้)
    // exceptProductId: สินค้าที่กำลังซื้อ/ต่ออายุ (ใช้ช่องเดิมของตัวเอง ไม่นับซ้ำ)
    public static function usedSlots(string $category, ?int $exceptProductId = null): int
    {
        $featured = Product::where('category', $category)
            ->where('featured_until', '>', now())
            ->pluck('id');

        $reserved = self::where('category', $category)->open()->pluck('product_id');

        return $featured->merge($reserved)
            ->map(fn ($id) => (int) $id)
            ->unique()
            ->reject(fn (int $id) => $id === $exceptProductId)
            ->count();
    }

    // อนุมัติ → สินค้าขึ้นช่องแนะนำ (ต่อจากวันหมดเดิมถ้ายังแนะนำอยู่)
    public function approve(User $admin): void
    {
        DB::transaction(function () use ($admin) {
            $product = Product::lockForUpdate()->findOrFail($this->product_id);

            [$start, $end] = self::nextPeriod($product->featured_until, $this->days);

            $product->forceFill(['featured_until' => $end])->save();

            $this->forceFill([
                'status' => self::STATUS_APPROVED,
                'reviewed_by' => $admin->id,
                'reviewed_at' => now(),
                'reject_reason' => null,
                'starts_at' => $start,
                'ends_at' => $end,
            ])->save();
        });

        $this->notifySeller(
            'ช่องแนะนำได้รับการอนุมัติ',
            '"' . $this->product->title . '" ขึ้นช่องสินค้าแนะนำถึง '
                . $this->ends_at->timezone(config('market.timezone'))->format('d/m/Y H:i') . ' น.',
            ['product_id' => $this->product_id]
        );
    }

    public function reject(User $admin, string $reason): void
    {
        $this->markRejected($admin, $reason);

        $this->notifySeller(
            'สลิปช่องแนะนำไม่ผ่าน',
            '"' . $this->product->title . '": ' . $reason,
            ['product_id' => $this->product_id]
        );
    }

    public function toSellerPayload(): array
    {
        return [
            ...$this->basePayload(),
            'product_id' => $this->product_id,
            'category' => $this->category,
            'product_title' => $this->product?->title,
        ];
    }
}
