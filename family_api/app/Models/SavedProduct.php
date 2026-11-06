<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// สินค้าที่ผู้ใช้กดบันทึกไว้ (ปุ่มบุ๊กมาร์กในหน้าสินค้า)
class SavedProduct extends Model
{
    protected $fillable = [
        'user_id',
        'product_id',
    ];

    public function product()
    {
        return $this->belongsTo(Product::class);
    }
}
