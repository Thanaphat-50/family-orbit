<?php

namespace App\Models\Concerns;

use App\Models\AppNotification;
use App\Models\User;
use App\Support\MediaStorage;
use App\Support\PromptPay;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use RuntimeException;

// =======================================================
// ส่วนที่ใช้ร่วมกันของคำสั่งซื้อช่องแนะนำ (สินค้า / ร้าน)
// awaiting_payment → (แนบสลิป) pending_review → approved / rejected
// awaiting_payment → cancelled (ยกเลิกเอง / หมดเวลาแนบสลิป)
// =======================================================

trait PromotionPayment
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

    // key ของแพ็กเกจใน config (เช่น market.promotion_plans)
    abstract public static function plansConfigKey(): string;

    // ลบสลิปเมื่อคำสั่งซื้อถูกลบ
    public static function bootPromotionPayment(): void
    {
        static::deleted(function (self $promotion) {
            $path = $promotion->slip_path;

            DB::afterCommit(fn () => MediaStorage::delete([$path]));
        });
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

    // รายการที่ยังไม่จบ: รอชำระ (ยังไม่หมดเวลา) / รอตรวจสลิป
    public function scopeOpen(Builder $query): Builder
    {
        return $query->where(fn (Builder $inner) => $inner
            ->where('status', self::STATUS_PENDING_REVIEW)
            ->orWhere(fn (Builder $awaiting) => $awaiting->awaitingInTime()));
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

    public function planLabel(): string
    {
        return config(static::plansConfigKey())[$this->plan]['label'] ?? $this->plan;
    }

    // คำสั่งซื้อรอชำระที่เลยเวลาแนบสลิป → ยกเลิก (คืนช่องที่จองไว้)
    public static function expireStale(): void
    {
        static::where('status', self::STATUS_AWAITING_PAYMENT)
            ->where('created_at', '<=', now()->subHours((int) config('market.promotion_payment_hours')))
            ->update(['status' => self::STATUS_CANCELLED, 'updated_at' => now()]);
    }

    public static function paymentEnabled(): bool
    {
        return PromptPay::isValidId(config('market.promptpay_id'));
    }

    public static function plansPayload(): array
    {
        return collect(config(static::plansConfigKey()))
            ->map(fn (array $plan, string $key) => [
                'key' => $key,
                'label' => $plan['label'],
                'days' => (int) $plan['days'],
                'price' => (int) $plan['price'],
            ])
            ->values()
            ->all();
    }

    // เก็บสลิปใหม่ → รอตรวจ (ลบสลิปเดิมถ้าเปลี่ยน) / เก็บไฟล์ไม่ได้ → exception
    public function attachSlip(UploadedFile $file): void
    {
        $path = $file->store('promotion_slips/' . $this->user_id, MediaStorage::disk())
            ?: throw new RuntimeException('Could not store the slip.');

        $old = $this->slip_path;

        $this->forceFill([
            'slip_path' => $path,
            'slip_uploaded_at' => now(),
            'status' => self::STATUS_PENDING_REVIEW,
        ])->save();

        MediaStorage::delete([$old]);
    }

    // ข้อมูลฝั่งผู้ขาย + ข้อมูลโอนเงิน (เฉพาะตอนรอชำระ)
    protected function basePayload(): array
    {
        $payload = [
            ...$this->only([
                'id', 'plan', 'days', 'amount', 'status',
                'reject_reason', 'starts_at', 'ends_at', 'slip_uploaded_at', 'created_at',
            ]),
            'plan_label' => $this->planLabel(),
            'status_label' => self::STATUS_LABELS[$this->status] ?? $this->status,
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

    protected function notifySeller(string $title, string $message, array $data): void
    {
        AppNotification::create([
            'user_id' => $this->user_id,
            'family_id' => null,
            'type' => 'promotion_status',
            'title' => $title,
            'message' => $message,
            'data' => [
                'promotion_id' => $this->id,
                'status' => $this->status,
                ...$data,
            ],
            'is_read' => false,
        ]);
    }

    protected function markRejected(User $admin, string $reason): void
    {
        $this->forceFill([
            'status' => self::STATUS_REJECTED,
            'reviewed_by' => $admin->id,
            'reviewed_at' => now(),
            'reject_reason' => $reason,
        ])->save();
    }

    // วันเริ่ม/วันหมดของรอบใหม่: ยังแนะนำอยู่ → ต่อจากวันหมดเดิม
    protected static function nextPeriod($currentUntil, int $days): array
    {
        $start = $currentUntil && $currentUntil->isFuture() ? $currentUntil->copy() : now();

        return [$start, $start->copy()->addDays($days)];
    }
}
