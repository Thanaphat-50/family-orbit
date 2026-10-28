<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

// =======================================================
// คำขอลบบัญชี
// ผู้ใช้ส่งคำขอ (แอป / หน้าเว็บ) → ผู้ดูแลกดลบในหน้า Admin
// =======================================================

class AccountDeletionRequest extends Model
{
    public const STATUS_PENDING = 'pending';
    public const STATUS_COMPLETED = 'completed';
    public const STATUS_CANCELED = 'canceled';
    public const STATUS_REJECTED = 'rejected';

    public const STATUS_LABELS = [
        self::STATUS_PENDING => 'รอดำเนินการ',
        self::STATUS_COMPLETED => 'ลบแล้ว',
        self::STATUS_CANCELED => 'ผู้ใช้ยกเลิก',
        self::STATUS_REJECTED => 'ไม่ลบ',
    ];

    // ระยะเวลาที่สัญญากับผู้ใช้ว่าจะลบให้เสร็จ (แสดงในแอปและนโยบาย)
    public const PROCESS_WITHIN_DAYS = 30;

    protected $fillable = [
        'user_id',
        'name',
        'email',
        'source',
        'reason',
        'status',
        'processed_by',
        'processed_at',
        'note',
    ];

    protected $casts = [
        'processed_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function processor()
    {
        return $this->belongsTo(User::class, 'processed_by');
    }

    public function scopePending(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_PENDING);
    }

    public function isPending(): bool
    {
        return $this->status === self::STATUS_PENDING;
    }

    // ส่งคำขอ (มีคำขอที่รออยู่แล้ว → ใช้อันเดิม)
    public static function requestFor(User $user, string $source, ?string $reason = null): self
    {
        $pending = self::pending()->where('user_id', $user->id)->first();

        if ($pending) {
            return $pending;
        }

        return self::create([
            'user_id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'source' => $source,
            'reason' => $reason !== null && trim($reason) !== '' ? trim($reason) : null,
            'status' => self::STATUS_PENDING,
        ]);
    }

    public function payload(): array
    {
        return [
            'id' => $this->id,
            'status' => $this->status,
            'created_at' => $this->created_at?->toIso8601String(),
            'process_within_days' => self::PROCESS_WITHIN_DAYS,
        ];
    }
}
