<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// ตัวเลือกสินค้า (สี ขนาด รุ่น) มีราคาและสต็อกของตัวเอง
// สินค้าที่มีตัวเลือก: products.stock = ผลรวมสต็อกของทุกตัวเลือก
class ProductVariant extends Model
{
    protected $fillable = [
        'product_id',
        'name',
        'price',
        'stock',
        'sort',
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'stock' => 'integer',
        'sort' => 'integer',
    ];

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    // ราคาที่ใช้จริง (ไม่ได้ตั้ง = ราคาสินค้า)
    public function effectivePrice(): ?float
    {
        $price = $this->price ?? $this->product?->price;

        return $price === null ? null : (float) $price;
    }

    public function toPayload(): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'price' => $this->effectivePrice(),
            'stock' => $this->stock,
            'sold_out' => $this->stock <= 0,
        ];
    }
}
