<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ProductReport extends Model
{
    protected $fillable = [
        'product_id',
        'user_id',
        'reason',
        'details',
    ];

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    // ผู้รายงาน
    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
