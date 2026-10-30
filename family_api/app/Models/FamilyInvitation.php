<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// =======================================================
// คำเชิญ / คำขอเข้าครอบครัว
// - invite:  คนในครอบครัวชวนผู้ใช้ (user_id) → ผู้ใช้กดรับ/ปฏิเสธ
// - request: ผู้ใช้ (user_id) ขอเข้าครอบครัว → Owner อนุมัติ/ปฏิเสธ
// =======================================================

class FamilyInvitation extends Model
{
    public const INVITE = 'invite';
    public const REQUEST = 'request';

    public const PENDING = 'pending';
    public const ACCEPTED = 'accepted';
    public const DECLINED = 'declined';
    public const CANCELED = 'canceled';

    protected $fillable = [
        'family_id',
        'user_id',
        'created_by',
        'type',
        'status',
        'responded_by',
        'responded_at',
    ];

    protected $casts = [
        'responded_at' => 'datetime',
    ];

    public function family()
    {
        return $this->belongsTo(Family::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function scopePending($query)
    {
        return $query->where('status', self::PENDING);
    }

    public function isPending(): bool
    {
        return $this->status === self::PENDING;
    }

    // ปิดคำเชิญ/คำขอที่ค้างอยู่ทั้งหมดของผู้ใช้ (เข้าครอบครัวได้แล้ว)
    public static function closePendingFor(User $user, ?int $exceptId = null): void
    {
        static::pending()
            ->where('user_id', $user->id)
            ->when($exceptId, fn ($query) => $query->whereKeyNot($exceptId))
            ->update([
                'status' => self::CANCELED,
                'responded_at' => now(),
            ]);
    }

    // ข้อมูลที่ส่งให้แอป
    public function payload(): array
    {
        $family = $this->family;

        return [
            'id' => $this->id,
            'type' => $this->type,
            'status' => $this->status,
            'created_at' => $this->created_at?->toIso8601String(),
            'family' => $family ? [
                'id' => $family->id,
                'name' => $family->name,
                'members_count' => $family->members()->count(),
                'owner' => $family->owner?->only(['id', 'name', 'profile_image_url']),
            ] : null,
            'user' => $this->user?->only(['id', 'name', 'profile_image_url']),
            'creator' => $this->creator?->only(['id', 'name', 'profile_image_url']),
        ];
    }
}
