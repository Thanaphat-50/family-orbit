<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

// รีวิวสินค้า 1–5 ดาวจากผู้ซื้อจริง (ผูกกับคำสั่งซื้อที่สำเร็จ) / Admin ซ่อนได้
class ProductReview extends Model
{
    protected $fillable = [
        'product_id',
        'order_id',
        'user_id',
        'shop_id',
        'rating',
        'comment',
        'variant_name',
        'hidden_at',
    ];

    protected $casts = [
        'rating' => 'integer',
        'hidden_at' => 'datetime',
    ];

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function shop()
    {
        return $this->belongsTo(Shop::class);
    }

    public function scopeVisible(Builder $query): Builder
    {
        return $query->whereNull('hidden_at');
    }

    public static function summaryFor(int $productId): array
    {
        $row = self::where('product_id', $productId)
            ->visible()
            ->selectRaw('count(*) as total, avg(rating) as average')
            ->first();

        $count = (int) ($row->total ?? 0);

        return [
            'count' => $count,
            'average' => $count > 0 ? round((float) $row->average, 1) : null,
        ];
    }

    public function toPayload(int $viewerId): array
    {
        return [
            ...$this->only(['id', 'rating', 'comment', 'variant_name', 'created_at', 'updated_at']),
            'is_mine' => (int) $this->user_id === $viewerId,
            // ผู้รีวิวซื้อสินค้านี้จริง (รีวิวได้เฉพาะคำสั่งซื้อที่สำเร็จ)
            'verified_purchase' => true,
            'user' => $this->user?->only(['id', 'name', 'profile_image_url', 'profile_photo_url']),
        ];
    }
}
