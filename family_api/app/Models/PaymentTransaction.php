<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// การชำระเงิน 1 ครั้ง (แนบสลิป 1 ครั้ง) ของคำสั่งซื้อ
class PaymentTransaction extends Model
{
    public const STATUS_VERIFIED = 'verified';
    public const STATUS_CONFIRMED = 'confirmed';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_REVIEW = 'review';

    public const STATUS_LABELS = [
        self::STATUS_VERIFIED => 'ระบบตรวจสลิปแล้ว ชำระสำเร็จ',
        self::STATUS_CONFIRMED => 'ร้านยืนยันว่าได้รับเงินแล้ว',
        self::STATUS_REJECTED => 'สลิปไม่ผ่าน',
        self::STATUS_REVIEW => 'รอร้านตรวจยอดเงิน',
    ];

    protected $fillable = [
        'order_id',
        'method',
        'amount',
        'status',
        'provider',
        'trans_ref',
        'slip_amount',
        'slip_date',
        'receiver_account',
        'reason',
        'verified_at',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'slip_amount' => 'decimal:2',
        'slip_date' => 'datetime',
        'verified_at' => 'datetime',
    ];

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function toPayload(): array
    {
        return [
            ...$this->only([
                'id', 'method', 'amount', 'status', 'slip_amount',
                'slip_date', 'reason', 'verified_at', 'created_at',
            ]),
            'status_label' => self::STATUS_LABELS[$this->status] ?? $this->status,
            'verified_by_system' => $this->provider !== 'manual' && $this->status === self::STATUS_VERIFIED,
        ];
    }
}
