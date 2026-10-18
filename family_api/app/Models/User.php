<?php

namespace App\Models;

use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use App\Support\MediaStorage;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable implements FilamentUser
{
    /** @use HasFactory<\Database\Factories\UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    protected $fillable = [
        'name',
        'email',
        'password',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'is_admin',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'community_terms_accepted_at' => 'datetime',
            'is_admin' => 'boolean',
        ];
    }

    // เข้าหน้า Admin (/admin) ได้เฉพาะผู้ดูแลระบบ
    public function canAccessPanel(Panel $panel): bool
    {
        return $this->is_admin === true;
    }

    // ผู้ใช้ที่เราบล็อก (ซ่อนโพสต์/ความคิดเห็นของเขาในฟีดชุมชน)
    public function blockedUsers()
    {
        return $this->belongsToMany(
            User::class,
            'user_blocks',
            'user_id',
            'blocked_user_id'
        )->withTimestamps();
    }

    protected $appends = [
        'profile_image_url',
        'profile_photo_url',
    ];

    public function getProfileImageUrlAttribute(): ?string
    {
        return $this->profilePhotoUrl();
    }

    public function getProfilePhotoUrlAttribute(): ?string
    {
        return $this->profilePhotoUrl();
    }

    // Disk ที่เก็บรูปโปรไฟล์ (ใช้ร่วมกับรูปในโพสต์)
    // ในเครื่องใช้ public / บน Cloud ใช้ Default Disk ที่เชื่อมกับ Bucket
    public static function profilePhotoDisk(): string
    {
        return MediaStorage::disk();
    }

    private function profilePhotoUrl(): ?string
    {
        return MediaStorage::url($this->profile_photo);
    }
}
