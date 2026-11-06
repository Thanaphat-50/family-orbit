<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// สินค้าในตะกร้า (ราคา/สต็อกอ่านใหม่ทุกครั้ง ไม่เก็บราคาไว้)
class CartItem extends Model
{
    protected $fillable = [
        'user_id',
        'product_id',
        'variant_id',
        'quantity',
    ];

    protected $casts = [
        'quantity' => 'integer',
    ];

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function variant()
    {
        return $this->belongsTo(ProductVariant::class, 'variant_id');
    }
}
