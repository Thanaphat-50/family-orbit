<?php

namespace App\Models;

use App\Services\PushNotifications;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Prunable;
use Illuminate\Support\Facades\DB;

use function Illuminate\Support\defer;

class AppNotification extends Model
{
    use Prunable;

    // ลบการแจ้งเตือนที่อ่านแล้วเมื่อเก่ากว่านี้ (วัน)
    public const PRUNE_READ_AFTER_DAYS = 90;

    // ข้อความแชทใหม่: แจ้งเตือนเด้งอย่างเดียว ไม่บันทึกในหน้าแจ้งเตือน
    public const TYPE_NEW_MESSAGE = 'new_message';

    // ประเภทที่ผู้ใช้เปิด/ปิดเองได้ในหน้าตั้งค่า
    // (ประเภทอื่น เช่น shop_status ส่งเสมอ)
    public const OPTIONAL_TYPES = [
        'new_post',
        'new_comment',
        'new_activity',
        'member_joined',
        self::TYPE_NEW_MESSAGE,
    ];

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

    // ไม่สร้างการแจ้งเตือนประเภทที่ผู้รับปิดไว้ในหน้าตั้งค่า
    // (ทุกที่ที่เรียก AppNotification::create จะผ่านตรงนี้)
    protected static function booted(): void
    {
        static::creating(function (AppNotification $notification) {
            if (!in_array($notification->type, self::OPTIONAL_TYPES, true)) {
                return true;
            }

            $recipient = User::find($notification->user_id, ['id', 'notification_settings']);

            return $recipient === null || $recipient->wantsNotification($notification->type);
        });

        // แจ้งเตือนเด้งบนมือถือ: หลังบันทึกสำเร็จ และหลังตอบแอปไปแล้ว (ไม่ทำให้ช้า)
        static::created(function (AppNotification $notification) {
            DB::afterCommit(function () use ($notification) {
                defer(fn () => app(PushNotifications::class)->sendNotification($notification));
            });
        });
    }

    // ลบอัตโนมัติด้วย php artisan model:prune (ตั้งเวลาไว้ใน routes/console.php)
    public function prunable(): Builder
    {
        return static::where('is_read', true)
            ->where('created_at', '<', now()->subDays(self::PRUNE_READ_AFTER_DAYS));
    }
}
