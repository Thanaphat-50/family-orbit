<?php

namespace App\Models;

use App\Services\MarketScreening;
use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

class Product extends Model
{
    public const STATUS_ACTIVE = 'active';
    public const STATUS_HIDDEN = 'hidden';

    protected $fillable = [
        'shop_id',
        'title',
        'description',
        'price',
        'stock',
        'shipping_fee',
        'category',
        'status',
        'hidden_at',
        'views',
        'video_path',
        'video_thumbnail_path',
        'card_media',
    ];

    protected $hidden = [
        'video_path',
        'video_thumbnail_path',
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'stock' => 'integer',
        'shipping_fee' => 'decimal:2',
        'hidden_at' => 'datetime',
        'views' => 'integer',
        'featured_until' => 'datetime',
    ];

    public function shop()
    {
        return $this->belongsTo(Shop::class);
    }

    public function images()
    {
        return $this->hasMany(ProductImage::class)->orderBy('sort');
    }

    public function reports()
    {
        return $this->hasMany(ProductReport::class);
    }

    public function promotions()
    {
        return $this->hasMany(ProductPromotion::class);
    }

    public function orders()
    {
        return $this->hasMany(Order::class);
    }

    public function isSoldOut(): bool
    {
        return (int) $this->stock <= 0;
    }

    // การ์ดสินค้าเล่นวิดีโอแทนรูป (ผู้ขายเลือก และมีวิดีโอแล้ว)
    public function showsVideoOnCard(): bool
    {
        return $this->card_media === 'video' && $this->video_path !== null;
    }

    // เหตุผลที่ผู้ใช้คนนี้สั่งซื้อในแอปไม่ได้ (null = สั่งได้) ต้องโหลด shop ไว้ก่อน
    public function orderBlockReason(User $user): ?string
    {
        return match (true) {
            (int) $this->shop->user_id === (int) $user->id => 'นี่คือสินค้าของร้านคุณ',
            $this->price === null => 'สินค้านี้ให้สอบถามราคากับร้านก่อน',
            $this->isSoldOut() => 'สินค้าหมดแล้ว',
            !$this->shop->acceptsOrders() => 'ร้านนี้ยังไม่เปิดรับคำสั่งซื้อในแอป ติดต่อร้านได้โดยตรง',
            default => null,
        };
    }

    // ขึ้นช่องแนะนำอยู่ตอนนี้
    public function isFeatured(): bool
    {
        return $this->featured_until !== null && $this->featured_until->isFuture();
    }

    public function scopeFeaturedNow(Builder $query): Builder
    {
        return $query->where('featured_until', '>', now());
    }

    public function getVideoUrlAttribute(): ?string
    {
        return MediaStorage::url($this->video_path);
    }

    public function getVideoThumbnailUrlAttribute(): ?string
    {
        return MediaStorage::url($this->video_thumbnail_path);
    }

    // ไฟล์ทั้งหมดของสินค้า (รูป วิดีโอ สลิป) ต้องโหลด images, promotions ไว้ก่อน
    public function mediaPaths(): array
    {
        return [
            ...$this->images->pluck('path')->all(),
            $this->video_path,
            $this->video_thumbnail_path,
            ...$this->promotions->pluck('slip_path')->all(),
        ];
    }

    // สินค้าที่ผู้ซื้อเห็นในตลาด:
    // เจ้าของร้านไม่ได้ซ่อน, ไม่ถูกซ่อนโดย Admin และร้านเปิดขายอยู่
    public function scopeVisibleInMarket(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_ACTIVE)
            ->whereNull('hidden_at')
            ->whereHas('shop', fn ($shops) => $shops->active());
    }

    // ลบไฟล์เมื่อสินค้าถูกลบด้วย $product->delete()
    // (โหลดรายการรูป/สลิปไว้ก่อน เพราะแถวถูกลบตาม cascade)
    protected static function booted(): void
    {
        // ลงสินค้าใหม่ / แก้ชื่อหรือรายละเอียด → ตรวจสินค้าต้องห้าม (พบ → แจ้งผู้ดูแล)
        static::saved(function (Product $product) {
            if ($product->wasRecentlyCreated || $product->wasChanged(['title', 'description'])) {
                app(MarketScreening::class)->screenProduct($product);
            }
        });

        static::deleting(function (Product $product) {
            $product->loadMissing(['images', 'promotions']);
        });

        static::deleted(function (Product $product) {
            MarketFlag::where('flaggable_type', Product::class)
                ->where('flaggable_id', $product->id)
                ->delete();

            $paths = $product->mediaPaths();

            DB::afterCommit(fn () => MediaStorage::delete($paths));
        });
    }
}
