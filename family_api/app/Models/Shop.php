<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;
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
        'featured_until',
        'terms_accepted_at',
    ];

    protected $hidden = [
        'logo_path',
    ];

    protected $appends = [
        'logo_url',
        'is_featured',
    ];

    protected $casts = [
        'approved_at' => 'datetime',
        'featured_until' => 'datetime',
        'terms_accepted_at' => 'datetime',
    ];

    public function owner()
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function products()
    {
        return $this->hasMany(Product::class);
    }

    public function reports()
    {
        return $this->hasMany(ShopReport::class);
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

    // ร้านแนะนำที่ยังไม่หมดเวลา (ร้านต้องเปิดขายอยู่ด้วย)
    public function scopeFeatured(Builder $query): Builder
    {
        return $query->active()
            ->whereNotNull('featured_until')
            ->where('featured_until', '>', now());
    }

    public function isFeatured(): bool
    {
        return $this->isActive()
            && $this->featured_until !== null
            && $this->featured_until->isFuture();
    }

    public function getIsFeaturedAttribute(): bool
    {
        return $this->isFeatured();
    }

    // =====================================================
    // ร้านแนะนำ (ตั้งโดย Admin) + แจ้งเจ้าของร้าน
    // =====================================================

    public function feature(\DateTimeInterface $until): void
    {
        // แปลงเป็น UTC ก่อนบันทึก (Laravel บันทึกเวลาโดยไม่แปลงเขตเวลาให้)
        $this->featured_until = Carbon::instance($until)->utc();
        $this->save();

        $this->notifyOwner(
            'ร้านของคุณขึ้นร้านแนะนำแล้ว',
            'ร้าน "' . $this->name . '" แสดงด้านบนของตลาดถึงวันที่ '
                . $this->featured_until->copy()->setTimezone(config('market.timezone'))->format('d/m/Y')
        );
    }

    public function unfeature(): void
    {
        $this->featured_until = null;
        $this->save();
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

    // ลบไฟล์โลโก้และรูปสินค้าทั้งหมดเมื่อร้านถูกลบด้วย $shop->delete()
    // (สินค้าและรูปถูกลบตาม cascade จึงต้องโหลด path ไว้ก่อน)
    protected static function booted(): void
    {
        static::deleting(function (Shop $shop) {
            $shop->loadMissing('products.images');
        });

        static::deleted(function (Shop $shop) {
            $paths = [
                $shop->logo_path,
                ...$shop->products->flatMap(fn (Product $product) => $product->images->pluck('path'))->all(),
            ];

            DB::afterCommit(fn () => MediaStorage::delete($paths));
        });
    }

    // path ของไฟล์ทั้งหมดในร้านของผู้ใช้ (โลโก้ + รูปสินค้า)
    // ใช้ตอนลบบัญชี ซึ่งร้านถูกลบผ่าน cascade ของฐานข้อมูล
    public static function mediaPathsOfOwner(int $userId): array
    {
        $shops = self::where('user_id', $userId)->get(['id', 'logo_path']);

        $productImages = ProductImage::whereIn(
            'product_id',
            Product::whereIn('shop_id', $shops->pluck('id'))->select('id')
        )->pluck('path');

        return [
            ...$shops->pluck('logo_path')->all(),
            ...$productImages->all(),
        ];
    }
}
