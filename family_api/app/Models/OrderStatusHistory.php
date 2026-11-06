<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// ประวัติสถานะคำสั่งซื้อ (ใคร เปลี่ยนเป็นอะไร เมื่อไร)
class OrderStatusHistory extends Model
{
    public const UPDATED_AT = null;

    protected $fillable = [
        'order_id',
        'status',
        'actor',
        'note',
    ];
}
