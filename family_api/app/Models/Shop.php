<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

class Shop extends Model
{
    public const STATUS_PENDING = 'pending';
    public const STATUS_ACTIVE = 'active';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_SUSPENDED = 'suspended';

    // ชื่อสถานะภาษาไทย (ใช้ในหน้า Admin และการแจ้งเตือน)
    public const STATUS_LABELS = [
        self::STATUS_PENDING => 'รออนุมัติ',
        self::STATUS_ACTIVE => 'เปิดขาย',
        self::STATUS_REJECTED => 'ไม่ผ่าน',
        self::STATUS_SUSPENDED => 'ถูกระงับ',
    ];

    protected $fillable = [
        'user_id',
        'name',
        'description',
        'category',
        'phone',
        'line_id',
        'province',
        'district',
        'logo_path',
        'status',
        'status_reason',
        'approved_at',
        'terms_accepted_at',
    ];

    protected $hidden = [
        'logo_path',
    ];

    protected $appends = [
        'logo_url',
    ];

    protected $casts = [
        'approved_at' => 'datetime',
        'terms_accepted_at' => 'datetime',
    ];

    public function owner()
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    // ร้านที่แสดงในตลาด
    public function scopeActive(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_ACTIVE);
    }

    public function isActive(): bool
    {
        return $this->status === self::STATUS_ACTIVE;
    }

    public function getLogoUrlAttribute(): ?string
    {
        return MediaStorage::url($this->logo_path);
    }

    // =====================================================
    // เปลี่ยนสถานะโดย Admin + แจ้งเจ้าของร้าน
    // =====================================================

    public function approve(): void
    {
        $this->status = self::STATUS_ACTIVE;
        $this->status_reason = null;
        $this->approved_at = $this->approved_at ?? now();
        $this->save();

        $this->notifyOwner(
            'ร้านของคุณเปิดขายแล้ว',
            'ร้าน "' . $this->name . '" ผ่านการตรวจสอบ เริ่มลงสินค้าได้เลย'
        );
    }

    public function reject(string $reason): void
    {
        $this->status = self::STATUS_REJECTED;
        $this->status_reason = $reason;
        $this->save();

        $this->notifyOwner(
            'ร้านยังไม่ผ่านการตรวจสอบ',
            'ร้าน "' . $this->name . '": ' . $reason
                . ' (แก้ไขข้อมูลแล้วส่งใหม่ได้)'
        );
    }

    public function suspend(string $reason): void
    {
        $this->status = self::STATUS_SUSPENDED;
        $this->status_reason = $reason;
        $this->save();

        $this->notifyOwner(
            'ร้านของคุณถูกระงับชั่วคราว',
            'ร้าน "' . $this->name . '": ' . $reason
        );
    }

    private function notifyOwner(string $title, string $message): void
    {
        AppNotification::create([
            'user_id' => $this->user_id,
            'family_id' => null,
            'type' => 'shop_status',
            'title' => $title,
            'message' => $message,
            'data' => [
                'shop_id' => $this->id,
                'status' => $this->status,
            ],
            'is_read' => false,
        ]);
    }

    // ลบไฟล์โลโก้เมื่อร้านถูกลบด้วย $shop->delete()
    protected static function booted(): void
    {
        static::deleted(function (Shop $shop) {
            $paths = [$shop->logo_path];

            DB::afterCommit(fn () => MediaStorage::delete($paths));
        });
    }
}
