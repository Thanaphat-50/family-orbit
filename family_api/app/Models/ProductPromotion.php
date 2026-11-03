<?php

namespace App\Models;

use App\Support\MediaStorage;
use App\Support\PromptPay;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

// =======================================================
// คำสั่งซื้อช่องแนะนำสินค้า
// awaiting_payment → (แนบสลิป) pending_review → approved / rejected
// awaiting_payment → cancelled (ยกเลิกเอง / หมดเวลาแนบสลิป)
// =======================================================

class ProductPromotion extends Model
{
    public const STATUS_AWAITING_PAYMENT = 'awaiting_payment';
    public const STATUS_PENDING_REVIEW = 'pending_review';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_CANCELLED = 'cancelled';

    public const STATUS_LABELS = [
        self::STATUS_AWAITING_PAYMENT => 'รอชำระเงิน',
        self::STATUS_PENDING_REVIEW => 'รอตรวจสลิป',
        self::STATUS_APPROVED => 'อนุมัติแล้ว',
        self::STATUS_REJECTED => 'ไม่ผ่าน',
        self::STATUS_CANCELLED => 'ยกเลิก',
    ];

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

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    // คำสั่งซื้อรอชำระที่ยังไม่หมดเวลาแนบสลิป
    public function scopeAwaitingInTime(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_AWAITING_PAYMENT)
            ->where('created_at', '>', now()->subHours((int) config('market.promotion_payment_hours')));
    }

    public function isExpired(): bool
    {
        return $this->status === self::STATUS_AWAITING_PAYMENT
            && $this->created_at->lte(now()->subHours((int) config('market.promotion_payment_hours')));
    }

    public function paymentDeadline()
    {
        return $this->created_at->copy()->addHours((int) config('market.promotion_payment_hours'));
    }

    public function getSlipUrlAttribute(): ?string
    {
        return MediaStorage::url($this->slip_path);
    }

    // จำนวนช่องที่ใช้อยู่ในหมวด (นับเป็นสินค้า): แนะนำอยู่ + มีคำสั่งซื้อรอตรวจ/รอชำระ (จองช่องไว้)
    // exceptProductId: สินค้าที่กำลังซื้อ/ต่ออายุ (ใช้ช่องเดิมของตัวเอง ไม่นับซ้ำ)
    public static function usedSlots(string $category, ?int $exceptProductId = null): int
    {
        $featured = Product::where('category', $category)
            ->where('featured_until', '>', now())
            ->pluck('id');

        $reserved = self::where('category', $category)
            ->where(fn ($query) => $query
                ->where('status', self::STATUS_PENDING_REVIEW)
                ->orWhere(fn ($awaiting) => $awaiting->awaitingInTime()))
            ->pluck('product_id');

        return $featured->merge($reserved)
            ->map(fn ($id) => (int) $id)
            ->unique()
            ->reject(fn (int $id) => $id === $exceptProductId)
            ->count();
    }

    public static function slotsPerCategory(): int
    {
        return (int) config('market.featured_slots_per_category');
    }

    // คำสั่งซื้อรอชำระที่เลยเวลาแนบสลิป → ยกเลิก (คืนช่องที่จองไว้)
    public static function expireStale(): void
    {
        self::where('status', self::STATUS_AWAITING_PAYMENT)
            ->where('created_at', '<=', now()->subHours((int) config('market.promotion_payment_hours')))
            ->update(['status' => self::STATUS_CANCELLED, 'updated_at' => now()]);
    }

    public static function paymentEnabled(): bool
    {
        return PromptPay::isValidId(config('market.promptpay_id'));
    }

    public static function plansPayload(): array
    {
        return collect(config('market.promotion_plans'))
            ->map(fn (array $plan, string $key) => [
                'key' => $key,
                'label' => $plan['label'],
                'days' => (int) $plan['days'],
                'price' => (int) $plan['price'],
            ])
            ->values()
            ->all();
    }

    // ข้อมูลฝั่งผู้ขาย + ข้อมูลโอนเงิน (เฉพาะตอนรอชำระ)
    public function toSellerPayload(): array
    {
        $payload = [
            ...$this->only([
                'id', 'product_id', 'plan', 'days', 'amount', 'category', 'status',
                'reject_reason', 'starts_at', 'ends_at', 'slip_uploaded_at', 'created_at',
            ]),
            'plan_label' => config('market.promotion_plans')[$this->plan]['label'] ?? $this->plan,
            'status_label' => self::STATUS_LABELS[$this->status] ?? $this->status,
            'product_title' => $this->product?->title,
            'has_slip' => $this->slip_path !== null,
            'payment_deadline' => $this->paymentDeadline(),
        ];

        if ($this->status === self::STATUS_AWAITING_PAYMENT && self::paymentEnabled()) {
            $id = (string) config('market.promptpay_id');

            $payload['payment'] = [
                'promptpay_payload' => PromptPay::payload($id, (float) $this->amount),
                'promptpay_id' => PromptPay::maskedId($id),
                'promptpay_name' => config('market.promptpay_name'),
            ];
        }

        return $payload;
    }

    // อนุมัติ → สินค้าขึ้นช่องแนะนำ (ต่อจากวันหมดเดิมถ้ายังแนะนำอยู่)
    public function approve(User $admin): void
    {
        DB::transaction(function () use ($admin) {
            $product = Product::lockForUpdate()->findOrFail($this->product_id);

            $start = $product->featured_until && $product->featured_until->isFuture()
                ? $product->featured_until->copy()
                : now();

            $end = $start->copy()->addDays($this->days);

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
            '"' . $this->product->title . '" ขึ้นช่องแนะนำถึง '
                . $this->ends_at->timezone(config('market.timezone'))->format('d/m/Y H:i') . ' น.'
        );
    }

    public function reject(User $admin, string $reason): void
    {
        $this->forceFill([
            'status' => self::STATUS_REJECTED,
            'reviewed_by' => $admin->id,
            'reviewed_at' => now(),
            'reject_reason' => $reason,
        ])->save();

        $this->notifySeller(
            'สลิปช่องแนะนำไม่ผ่าน',
            '"' . $this->product->title . '": ' . $reason
        );
    }

    private function notifySeller(string $title, string $message): void
    {
        AppNotification::create([
            'user_id' => $this->user_id,
            'family_id' => null,
            'type' => 'promotion_status',
            'title' => $title,
            'message' => $message,
            'data' => [
                'promotion_id' => $this->id,
                'product_id' => $this->product_id,
                'status' => $this->status,
            ],
            'is_read' => false,
        ]);
    }

    protected static function booted(): void
    {
        static::deleted(function (ProductPromotion $promotion) {
            $path = $promotion->slip_path;

            DB::afterCommit(fn () => MediaStorage::delete([$path]));
        });
    }
}
