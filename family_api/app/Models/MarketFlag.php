<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

// =======================================================
// รายการตรวจพบสินค้า/ร้านที่อาจผิดกฎหมาย (ระบบตรวจคำอัตโนมัติ)
// open → dismissed (ผู้ดูแลดูแล้วไม่ผิดกฎ) / actioned (ซ่อนสินค้า / ระงับร้าน)
// ตรวจพบ → ระบบซ่อนสินค้า / ปิดร้านเองทันที (auto_hidden) จนกว่าผู้ดูแลจะตรวจ
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
        'auto_hidden',
        'reviewed_by',
        'reviewed_at',
    ];

    protected $casts = [
        'categories' => 'array',
        'terms' => 'array',
        'auto_hidden' => 'boolean',
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

    // ผู้ดูแลตรวจแล้วไม่ผิดกฎ → แสดงสินค้า / เปิดร้านคืน (ถ้าระบบเป็นคนซ่อน)
    public function dismiss(User $admin): void
    {
        $this->close($admin, self::STATUS_DISMISSED);

        if (!$this->auto_hidden) {
            return;
        }

        $item = $this->flaggable;

        if ($item instanceof Product && $item->hidden_at !== null) {
            $item->forceFill(['hidden_at' => null])->save();

            AppNotification::create([
                'user_id' => $item->shop->user_id,
                'family_id' => null,
                'type' => 'shop_status',
                'title' => 'สินค้าแสดงตามปกติแล้ว',
                'message' => 'ทีมงานตรวจ "' . $item->title . '" แล้ว ไม่ผิดกฎ สินค้ากลับมาแสดงในหน้าร้านค้า',
                'data' => ['shop_id' => $item->shop_id, 'product_id' => $item->id],
                'is_read' => false,
            ]);
        }

        if ($item instanceof Shop
            && $item->status === Shop::STATUS_SUSPENDED
            && $item->status_reason === Shop::AUTO_SCREEN_REASON) {
            $item->approve();
        }
    }
}
