<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

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

    public function images()
    {
        return $this->hasMany(PostImage::class)->orderBy('sort');
    }

    // ลบไฟล์รูปใน storage เมื่อโพสต์ถูกลบด้วย $post->delete()
    // (API ลบโพสต์ และปุ่มลบในหน้า Admin)
    //
    // โหลดรายการรูปไว้ก่อนลบ เพราะแถวใน post_images
    // จะถูกลบตามไปด้วย cascade และลบไฟล์หลัง Transaction สำเร็จ
    protected static function booted(): void
    {
        static::deleting(function (Post $post) {
            $post->loadMissing('images');
        });

        static::deleted(function (Post $post) {
            $paths = $post->images->pluck('path')->all();

            DB::afterCommit(fn () => MediaStorage::delete($paths));
        });
    }

    // โพสต์ที่ผู้ใช้ทุกคนในแอปเห็นได้
    public function isCommunity(): bool
    {
        return $this->visibility === 'community';
    }
}
