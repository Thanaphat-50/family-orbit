<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserBlock extends Model
{
    protected $fillable = [
        'user_id',
        'blocked_user_id',
    ];

    // ผู้บล็อก
    public function user()
    {
        return $this->belongsTo(User::class);
    }

    // ผู้ถูกบล็อก
    public function blockedUser()
    {
        return $this->belongsTo(User::class, 'blocked_user_id');
    }
}
