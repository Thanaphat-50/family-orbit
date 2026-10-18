<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Post extends Model
{
    // หมวดหมู่ของโพสต์ชุมชน (โพสต์ครอบครัวไม่มีหมวด)
    public const CATEGORIES = [
        'general',
        'qa',
        'news',
        'help',
        'event',
    ];

    protected $fillable = [
        'family_id',
        'user_id',
        'visibility',
        'category',
        'content',
    ];

    protected $casts = [
        'hidden_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function family()
    {
        return $this->belongsTo(Family::class);
    }

    public function comments()
    {
        return $this->hasMany(Comment::class)->oldest();
    }

    public function reports()
    {
        return $this->hasMany(PostReport::class);
    }

    public function likes()
    {
        return $this->hasMany(PostLike::class);
    }

    // โพสต์ที่ผู้ใช้ทุกคนในแอปเห็นได้
    public function isCommunity(): bool
    {
        return $this->visibility === 'community';
    }
}
