<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class Comment extends Model
{
    // ไฟล์แนบในความคิดเห็น (1 ไฟล์)
    public const MEDIA_IMAGE = 'image';
    public const MEDIA_GIF = 'gif';
    public const MEDIA_VIDEO = 'video';

    protected $fillable = [
        'post_id',
        'user_id',
        'content',
        'media_type',
        'media_path',
        'media_thumbnail_path',
        'media_width',
        'media_height',
    ];

    protected $casts = [
        'hidden_at' => 'datetime',
    ];

    // ส่งให้แอปเฉพาะลิงก์ (ไม่ส่งที่อยู่ไฟล์จริง)
    protected $hidden = [
        'media_path',
        'media_thumbnail_path',
    ];

    protected $appends = [
        'media',
    ];

    public function post()
    {
        return $this->belongsTo(Post::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function reports()
    {
        return $this->hasMany(CommentReport::class);
    }

    // {type, url, thumbnail_url, width, height} หรือ null ถ้าไม่มีไฟล์แนบ
    public function getMediaAttribute(): ?array
    {
        if (!$this->media_type || !$this->media_path) {
            return null;
        }

        return [
            'type' => $this->media_type,
            'url' => MediaStorage::url($this->media_path),
            'thumbnail_url' => MediaStorage::url($this->media_thumbnail_path),
            'width' => $this->media_width,
            'height' => $this->media_height,
        ];
    }

    // รูปตัวอย่างในหน้า Admin (วิดีโอใช้รูปตัวอย่างของวิดีโอ)
    public function getMediaPreviewUrlAttribute(): ?string
    {
        if (!$this->media_path) {
            return null;
        }

        return MediaStorage::url(
            $this->media_type === self::MEDIA_VIDEO ? $this->media_thumbnail_path : $this->media_path
        );
    }

    public function mediaPaths(): array
    {
        return array_values(array_filter([
            $this->media_path,
            $this->media_thumbnail_path,
        ]));
    }

    // ข้อความสั้น ๆ สำหรับประวัติการใช้งาน (ความคิดเห็นที่มีแต่ไฟล์ก็มีข้อความ)
    public function excerpt(): string
    {
        $content = trim((string) $this->content);

        if ($content !== '') {
            return Str::limit($content, 80);
        }

        return match ($this->media_type) {
            self::MEDIA_GIF => 'ส่ง GIF',
            self::MEDIA_VIDEO => 'ส่งวิดีโอ',
            default => 'ส่งรูป',
        };
    }

    // ลบความคิดเห็น (เจ้าของ / Admin) → ลบไฟล์แนบหลังลบข้อมูลสำเร็จ
    // (ลบตามโพสต์/บัญชีแบบ cascade ใช้ Post::mediaPathsOf แทน)
    protected static function booted(): void
    {
        static::deleted(function (Comment $comment) {
            $paths = $comment->mediaPaths();

            if ($paths !== []) {
                DB::afterCommit(fn () => MediaStorage::delete($paths));
            }
        });
    }
}
