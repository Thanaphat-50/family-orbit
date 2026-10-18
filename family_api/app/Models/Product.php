<?php

namespace App\Models;

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
        'category',
        'status',
        'hidden_at',
        'views',
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'hidden_at' => 'datetime',
        'views' => 'integer',
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

    // สินค้าที่ผู้ซื้อเห็นในตลาด:
    // เจ้าของร้านไม่ได้ซ่อน, ไม่ถูกซ่อนโดย Admin และร้านเปิดขายอยู่
    public function scopeVisibleInMarket(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_ACTIVE)
            ->whereNull('hidden_at')
            ->whereHas('shop', fn ($shops) => $shops->active());
    }

    // ลบไฟล์รูปเมื่อสินค้าถูกลบด้วย $product->delete()
    // (โหลดรายการรูปไว้ก่อน เพราะแถวรูปถูกลบตาม cascade)
    protected static function booted(): void
    {
        static::deleting(function (Product $product) {
            $product->loadMissing('images');
        });

        static::deleted(function (Product $product) {
            $paths = $product->images->pluck('path')->all();

            DB::afterCommit(fn () => MediaStorage::delete($paths));
        });
    }
}
