<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// สินค้า 1 รายการในคำสั่งซื้อ (เก็บชื่อและราคาตอนสั่งไว้)
class OrderItem extends Model
{
    protected $fillable = [
        'order_id',
        'product_id',
        'variant_id',
        'title',
        'variant_name',
        'unit_price',
        'quantity',
        'subtotal',
    ];

    protected $casts = [
        'unit_price' => 'decimal:2',
        'subtotal' => 'decimal:2',
        'quantity' => 'integer',
    ];

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function toPayload(): array
    {
        return [
            ...$this->only([
                'id', 'product_id', 'variant_id', 'title', 'variant_name',
                'unit_price', 'quantity', 'subtotal',
            ]),
            'image_url' => $this->product?->images->first()?->url,
        ];
    }
}
