<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Model;

class PostImage extends Model
{
    protected $fillable = [
        'post_id',
        'path',
        'sort',
    ];

    // ส่งให้แอปเฉพาะ id, sort และ url
    protected $hidden = [
        'post_id',
        'path',
        'created_at',
        'updated_at',
    ];

    protected $appends = [
        'url',
    ];

    public function post()
    {
        return $this->belongsTo(Post::class);
    }

    public function getUrlAttribute(): ?string
    {
        return MediaStorage::url($this->path);
    }
}
