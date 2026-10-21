<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Laravel\Sanctum\PersonalAccessToken;

class DeviceToken extends Model
{
    // เก็บไม่เกินกี่เครื่องต่อผู้ใช้ (เครื่องที่ไม่ได้เปิดนานสุดถูกลบก่อน)
    public const MAX_PER_USER = 10;

    protected $fillable = [
        'user_id',
        'access_token_id',
        'token',
        'platform',
        'last_used_at',
    ];

    protected $hidden = [
        'token',
    ];

    protected $casts = [
        'last_used_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    // การล็อกอินในแอปที่ลงทะเบียนเครื่องนี้
    public function accessToken()
    {
        return $this->belongsTo(PersonalAccessToken::class, 'access_token_id');
    }

    // เครื่องที่ยังล็อกอินอยู่ (Token ของแอปยังไม่หมดอายุ)
    public function scopeLoggedIn(Builder $query): Builder
    {
        return $query->whereHas('accessToken', function ($tokens) {
            $tokens->where(function ($valid) {
                $valid->whereNull('expires_at')
                    ->orWhere('expires_at', '>', now());
            });

            $expiration = config('sanctum.expiration');

            if ($expiration) {
                $tokens->where('created_at', '>', now()->subMinutes($expiration));
            }
        });
    }
}
