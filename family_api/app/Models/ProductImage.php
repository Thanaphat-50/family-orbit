<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Model;

class ProductImage extends Model
{
    protected $fillable = [
        'product_id',
        'path',
        'sort',
    ];

    // ส่งให้แอปเฉพาะ id, sort และ url
    protected $hidden = [
        'product_id',
        'path',
        'created_at',
        'updated_at',
    ];

    protected $appends = [
        'url',
    ];

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function getUrlAttribute(): ?string
    {
        return MediaStorage::url($this->path);
    }
}
