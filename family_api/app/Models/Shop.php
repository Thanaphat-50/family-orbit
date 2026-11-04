<?php

namespace App\Models;

use App\Services\MarketScreening;
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

    // เหตุผลที่ระบบปิดร้านเอง (ผู้ดูแลตรวจแล้วไม่ผิด → เปิดคืน)
    public const AUTO_SCREEN_REASON = 'ระบบพบคำที่อาจผิดกฎในชื่อหรือคำอธิบายร้าน ปิดไว้ชั่วคราวรอทีมงานตรวจสอบ';
    public const AUTO_REPORT_REASON = 'ร้านถูกรายงานจากผู้ใช้หลายคน ปิดไว้ชั่วคราวรอทีมงานตรวจสอบ';

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
        'opening_hours',
        'delivery_methods',
        'logo_path',
        'video_path',
        'video_thumbnail_path',
        'status',
        'status_reason',
        'approved_at',
        'featured_until',
        'terms_accepted_at',
    ];

    protected $hidden = [
        'logo_path',
        'video_path',
        'video_thumbnail_path',
    ];

    protected $appends = [
        'logo_url',
        'is_featured',
        'video_url',
        'video_thumbnail_url',
    ];

    protected $casts = [
        'delivery_methods' => 'array',
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

    public function images()
    {
        return $this->hasMany(ShopImage::class)->orderBy('sort')->orderBy('id');
    }

    public function reviews()
    {
        return $this->hasMany(ShopReview::class);
    }

    public function promotions()
    {
        return $this->hasMany(ShopPromotion::class);
    }

    public function getVideoUrlAttribute(): ?string
    {
        return MediaStorage::url($this->video_path);
    }

    public function getVideoThumbnailUrlAttribute(): ?string
    {
        return MediaStorage::url($this->video_thumbnail_path);
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

    // ลบไฟล์ทั้งหมดของร้านเมื่อร้านถูกลบด้วย $shop->delete()
    // (สินค้า รูป และสลิปถูกลบตาม cascade จึงต้องโหลด path ไว้ก่อน)
    protected static function booted(): void
    {
        // เปิดร้าน / แก้ชื่อหรือคำอธิบาย → ตรวจคำต้องห้าม (พบ → แจ้งผู้ดูแล)
        static::saved(function (Shop $shop) {
            if ($shop->wasRecentlyCreated || $shop->wasChanged(['name', 'description'])) {
                app(MarketScreening::class)->screenShop($shop);
            }
        });

        static::deleting(function (Shop $shop) {
            $shop->loadMissing(['images', 'promotions', 'products.images', 'products.promotions']);
        });

        static::deleted(function (Shop $shop) {
            $paths = [
                $shop->logo_path,
                $shop->video_path,
                $shop->video_thumbnail_path,
                ...$shop->images->pluck('path')->all(),
                ...$shop->promotions->pluck('slip_path')->all(),
                ...$shop->products->flatMap(fn (Product $product) => $product->mediaPaths())->all(),
            ];

            DB::afterCommit(fn () => MediaStorage::delete($paths));
        });
    }

    // path ของไฟล์ทั้งหมดในร้านของผู้ใช้ (โลโก้ วิดีโอ รูปร้าน รูป/วิดีโอสินค้า สลิป)
    // ใช้ตอนลบบัญชี ซึ่งร้านถูกลบผ่าน cascade ของฐานข้อมูล
    public static function mediaPathsOfOwner(int $userId): array
    {
        $shops = self::where('user_id', $userId)->get(['id', 'logo_path', 'video_path', 'video_thumbnail_path']);

        $products = Product::whereIn('shop_id', $shops->pluck('id'))
            ->get(['id', 'video_path', 'video_thumbnail_path']);

        return [
            ...$shops->flatMap(fn (Shop $shop) => [$shop->logo_path, $shop->video_path, $shop->video_thumbnail_path])->all(),
            ...ShopImage::whereIn('shop_id', $shops->pluck('id'))->pluck('path')->all(),
            ...$products->flatMap(fn (Product $product) => [$product->video_path, $product->video_thumbnail_path])->all(),
            ...ProductImage::whereIn('product_id', $products->pluck('id'))->pluck('path')->all(),
            ...ProductPromotion::where('user_id', $userId)->pluck('slip_path')->all(),
            ...ShopPromotion::where('user_id', $userId)->pluck('slip_path')->all(),
        ];
    }
}
