<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

// รีวิวร้าน 1–5 ดาว (1 คนต่อ 1 ร้าน) / Admin ซ่อนได้ (hidden_at)
class ShopReview extends Model
{
    public const MAX_COMMENT = 500;

    protected $fillable = [
        'shop_id',
        'user_id',
        'rating',
        'comment',
        'hidden_at',
    ];

    protected $casts = [
        'rating' => 'integer',
        'hidden_at' => 'datetime',
    ];

    public function shop()
    {
        return $this->belongsTo(Shop::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function scopeVisible(Builder $query): Builder
    {
        return $query->whereNull('hidden_at');
    }

    // คะแนนเฉลี่ย (เฉพาะรีวิวที่ไม่ถูกซ่อน)
    public static function summaryFor(int $shopId): array
    {
        $row = self::where('shop_id', $shopId)
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
            ...$this->only(['id', 'rating', 'comment', 'created_at', 'updated_at']),
            'is_mine' => (int) $this->user_id === $viewerId,
            'user' => $this->user?->only(['id', 'name', 'profile_image_url', 'profile_photo_url']),
        ];
    }
}
