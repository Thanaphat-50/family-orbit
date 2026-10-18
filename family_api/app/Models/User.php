<?php

namespace App\Models;

use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\HasApiTokens;
use Throwable;

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

    // Disk ที่เก็บรูปโปรไฟล์
    // ในเครื่องใช้ public / บน Cloud ใช้ Default Disk ที่เชื่อมกับ Bucket
    public static function profilePhotoDisk(): string
    {
        $default = config(
            'filesystems.default',
            'local'
        );

        return $default === 'local'
            ? 'public'
            : $default;
    }

    private function profilePhotoUrl(): ?string
    {
        if (!$this->profile_photo) {
            return null;
        }

        $disk = self::profilePhotoDisk();

        // สำหรับการพัฒนาในเครื่อง
        if ($disk === 'public') {
            return request()->getSchemeAndHttpHost()
                . '/storage/'
                . ltrim($this->profile_photo, '/');
        }

        // สำหรับ Private Bucket บน Cloud
        try {
            return Storage::disk($disk)->temporaryUrl(
                $this->profile_photo,
                now()->addHours(12)
            );
        } catch (Throwable $e) {
            Log::warning(
                'Cannot generate profile photo URL',
                [
                    'user_id' => $this->id,
                    'error' => $e->getMessage(),
                ]
            );

            return null;
        }
    }
}
