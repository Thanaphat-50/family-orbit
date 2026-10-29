<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// =======================================================
// ประวัติการใช้งาน (เจ้าของเห็นคนเดียว)
// like / comment / share / follow
// ใช้จัดฟีด "สำหรับคุณ" และแนะนำคนที่ชอบคล้ายกันด้วย
// =======================================================

class Interaction extends Model
{
    public const LIKE = 'like';
    public const COMMENT = 'comment';
    public const SHARE = 'share';
    public const FOLLOW = 'follow';

    // แชร์ไปที่ไหน (meta.channel)
    public const SHARE_CHANNELS = ['external', 'community', 'family'];

    protected $fillable = [
        'user_id',
        'type',
        'post_id',
        'target_user_id',
        'meta',
    ];

    protected $casts = [
        'meta' => 'array',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function post()
    {
        return $this->belongsTo(Post::class);
    }

    public function targetUser()
    {
        return $this->belongsTo(User::class, 'target_user_id');
    }

    public static function record(
        User $user,
        string $type,
        ?Post $post = null,
        ?User $target = null,
        ?array $meta = null
    ): self {
        return static::create([
            'user_id' => $user->id,
            'type' => $type,
            'post_id' => $post?->id,
            'target_user_id' => $target?->id ?? $post?->user_id,
            'meta' => $meta,
        ]);
    }

    // ยกเลิกถูกใจ / เลิกติดตาม → ลบออกจากประวัติด้วย
    public static function forget(User $user, string $type, ?Post $post = null, ?User $target = null): void
    {
        static::where('user_id', $user->id)
            ->where('type', $type)
            ->when($post, fn ($query) => $query->where('post_id', $post->id))
            ->when($target, fn ($query) => $query->where('target_user_id', $target->id))
            ->delete();
    }
}
