<?php

namespace App\Models;

use App\Models\Concerns\PromotionPayment;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

// =======================================================
// คำสั่งซื้อช่อง "ร้านแนะนำ" (แบนเนอร์ใหญ่บนสุด ราคาแพงกว่า)
// ช่องรวมทั้งแอป config('market.featured_slots') / สถานะดู Concerns\PromotionPayment
// =======================================================

class ShopPromotion extends Model
{
    use PromotionPayment;

    protected $fillable = [
        'shop_id',
        'user_id',
        'plan',
        'days',
        'amount',
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
        return 'market.shop_promotion_plans';
    }

    public function shop()
    {
        return $this->belongsTo(Shop::class);
    }

    public static function slots(): int
    {
        return (int) config('market.featured_slots');
    }

    // ช่องที่ใช้อยู่ (นับเป็นร้าน): แนะนำอยู่ + มีคำสั่งซื้อรอตรวจ/รอชำระ
    public static function usedSlots(?int $exceptShopId = null): int
    {
        $featured = Shop::featured()->pluck('id');

        $reserved = self::open()->pluck('shop_id');

        return $featured->merge($reserved)
            ->map(fn ($id) => (int) $id)
            ->unique()
            ->reject(fn (int $id) => $id === $exceptShopId)
            ->count();
    }

    // อนุมัติ → ร้านขึ้นแบนเนอร์ร้านแนะนำ (ต่อจากวันหมดเดิมถ้ายังแนะนำอยู่)
    public function approve(User $admin): void
    {
        DB::transaction(function () use ($admin) {
            $shop = Shop::lockForUpdate()->findOrFail($this->shop_id);

            [$start, $end] = self::nextPeriod($shop->featured_until, $this->days);

            $shop->forceFill(['featured_until' => $end])->save();

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
            'ร้านแนะนำได้รับการอนุมัติ',
            'ร้าน "' . $this->shop->name . '" ขึ้นช่องร้านแนะนำถึง '
                . $this->ends_at->timezone(config('market.timezone'))->format('d/m/Y H:i') . ' น.',
            ['shop_id' => $this->shop_id]
        );
    }

    public function reject(User $admin, string $reason): void
    {
        $this->markRejected($admin, $reason);

        $this->notifySeller(
            'สลิปร้านแนะนำไม่ผ่าน',
            'ร้าน "' . $this->shop->name . '": ' . $reason,
            ['shop_id' => $this->shop_id]
        );
    }

    public function toSellerPayload(): array
    {
        return [
            ...$this->basePayload(),
            'shop_id' => $this->shop_id,
            'shop_name' => $this->shop?->name,
        ];
    }
}
