<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Model;

class PostVideo extends Model
{
    // ความยาวและขนาดสูงสุด (แอปบีบอัดก่อนส่ง)
    public const MAX_SECONDS = 60;
    public const MAX_KB = 51200;

    protected $fillable = [
        'post_id',
        'path',
        'thumbnail_path',
        'duration_seconds',
        'size_bytes',
        'width',
        'height',
    ];

    // ส่งให้แอปเฉพาะลิงก์ (ไม่ส่งที่อยู่ไฟล์จริง)
    protected $hidden = [
        'post_id',
        'path',
        'thumbnail_path',
        'size_bytes',
        'created_at',
        'updated_at',
    ];

    protected $appends = [
        'url',
        'thumbnail_url',
    ];

    public function post()
    {
        return $this->belongsTo(Post::class);
    }

    public function getUrlAttribute(): ?string
    {
        return MediaStorage::url($this->path);
    }

    public function getThumbnailUrlAttribute(): ?string
    {
        return MediaStorage::url($this->thumbnail_path);
    }

    public function filePaths(): array
    {
        return array_values(array_filter([$this->path, $this->thumbnail_path]));
    }
}
