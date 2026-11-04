<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

// =======================================================
// รายการตรวจพบสินค้า/ร้านที่อาจผิดกฎหมาย (ระบบตรวจคำอัตโนมัติ)
// open → dismissed (ผู้ดูแลดูแล้วไม่ผิดกฎ) / actioned (ซ่อนสินค้า / ระงับร้าน)
// =======================================================

class MarketFlag extends Model
{
    public const STATUS_OPEN = 'open';
    public const STATUS_DISMISSED = 'dismissed';
    public const STATUS_ACTIONED = 'actioned';

    public const STATUS_LABELS = [
        self::STATUS_OPEN => 'รอตรวจ',
        self::STATUS_DISMISSED => 'ไม่ผิดกฎ',
        self::STATUS_ACTIONED => 'จัดการแล้ว',
    ];

    protected $fillable = [
        'flaggable_type',
        'flaggable_id',
        'shop_id',
        'categories',
        'terms',
        'fingerprint',
        'excerpt',
        'status',
        'reviewed_by',
        'reviewed_at',
    ];

    protected $casts = [
        'categories' => 'array',
        'terms' => 'array',
        'reviewed_at' => 'datetime',
    ];

    public function flaggable()
    {
        return $this->morphTo();
    }

    public function shop()
    {
        return $this->belongsTo(Shop::class);
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function scopeOpen(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_OPEN);
    }

    // "บุหรี่ / บุหรี่ไฟฟ้า, อาวุธ"
    public function categoryLabels(): string
    {
        $labels = collect($this->categories ?? [])
            ->map(fn (string $key) => config("market.prohibited.{$key}.label", $key));

        return $labels->implode(', ');
    }

    public function isProduct(): bool
    {
        return $this->flaggable_type === Product::class;
    }

    // ชื่อสินค้า / ร้านที่ตรวจพบ
    public function itemName(): string
    {
        $item = $this->flaggable;

        return match (true) {
            $item instanceof Product => $item->title,
            $item instanceof Shop => $item->name,
            default => '(ถูกลบแล้ว)',
        };
    }

    public function close(User $admin, string $status): void
    {
        $this->forceFill([
            'status' => $status,
            'reviewed_by' => $admin->id,
            'reviewed_at' => now(),
        ])->save();
    }
}
