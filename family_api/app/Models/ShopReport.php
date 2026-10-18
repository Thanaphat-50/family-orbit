<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ShopReport extends Model
{
    protected $fillable = [
        'shop_id',
        'user_id',
        'reason',
        'details',
    ];

    public function shop()
    {
        return $this->belongsTo(Shop::class);
    }

    // ผู้รายงาน
    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
