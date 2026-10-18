<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CommentReport extends Model
{
    protected $fillable = [
        'comment_id',
        'user_id',
        'reason',
        'details',
    ];

    public function comment()
    {
        return $this->belongsTo(Comment::class);
    }

    // ผู้รายงาน
    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
