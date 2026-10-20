<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Prunable;

class AppNotification extends Model
{
    use Prunable;

    // ลบการแจ้งเตือนที่อ่านแล้วเมื่อเก่ากว่านี้ (วัน)
    public const PRUNE_READ_AFTER_DAYS = 90;

    protected $fillable = [
        'user_id',
        'family_id',
        'type',
        'title',
        'message',
        'data',
        'is_read',
    ];

    protected $casts = [
        'data' => 'array',
        'is_read' => 'boolean',
    ];

    public function user()
    {
        return $this->belongsTo(
            User::class
        );
    }

    public function family()
    {
        return $this->belongsTo(
            Family::class
        );
    }

    // ลบอัตโนมัติด้วย php artisan model:prune (ตั้งเวลาไว้ใน routes/console.php)
    public function prunable(): Builder
    {
        return static::where('is_read', true)
            ->where('created_at', '<', now()->subDays(self::PRUNE_READ_AFTER_DAYS));
    }
}
