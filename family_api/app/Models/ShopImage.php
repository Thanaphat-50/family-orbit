<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Model;

// รูปหน้าร้าน (ไม่เกิน config('market.max_shop_images') รูป)
class ShopImage extends Model
{
    protected $fillable = [
        'shop_id',
        'path',
        'sort',
    ];

    protected $hidden = [
        'shop_id',
        'path',
        'sort',
        'created_at',
        'updated_at',
    ];

    protected $appends = [
        'url',
    ];

    public function shop()
    {
        return $this->belongsTo(Shop::class);
    }

    public function getUrlAttribute(): ?string
    {
        return MediaStorage::url($this->path);
    }
}
