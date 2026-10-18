<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PostReport extends Model
{
    protected $fillable = [
        'post_id',
        'user_id',
        'reason',
        'details',
    ];

    public function post()
    {
        return $this->belongsTo(Post::class);
    }

    // ผู้รายงาน
    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
