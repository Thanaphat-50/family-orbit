<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

// =======================================================
// ห้องแชทส่วนตัว 2 คน
// user_one_id < user_two_id เสมอ (1 คู่มีห้องเดียว)
// =======================================================

class Conversation extends Model
{
    protected $fillable = [
        'user_one_id',
        'user_two_id',
        'user_one_read_id',
        'user_two_read_id',
        'last_message_at',
    ];

    protected $casts = [
        'last_message_at' => 'datetime',
    ];

    public function messages()
    {
        return $this->hasMany(ChatMessage::class);
    }

    // ห้องของคู่นี้ (ยังไม่มี → สร้างใหม่)
    public static function between(int $userId, int $otherId): self
    {
        return self::firstOrCreate([
            'user_one_id' => min($userId, $otherId),
            'user_two_id' => max($userId, $otherId),
        ]);
    }

    // ห้องที่ผู้ใช้คนนี้อยู่
    public function scopeOf(Builder $query, int $userId): Builder
    {
        return $query->where(function ($rooms) use ($userId) {
            $rooms->where('user_one_id', $userId)
                ->orWhere('user_two_id', $userId);
        });
    }

    public function hasMember(int $userId): bool
    {
        return (int) $this->user_one_id === $userId
            || (int) $this->user_two_id === $userId;
    }

    public function otherUserId(int $userId): int
    {
        return (int) $this->user_one_id === $userId
            ? (int) $this->user_two_id
            : (int) $this->user_one_id;
    }

    public function readColumn(int $userId): string
    {
        return (int) $this->user_one_id === $userId
            ? 'user_one_read_id'
            : 'user_two_read_id';
    }

    public function lastReadId(int $userId): int
    {
        return (int) ($this->{$this->readColumn($userId)} ?? 0);
    }

    // จำนวนข้อความจากอีกฝ่ายที่ผู้ใช้ยังไม่อ่าน
    public function unreadCountFor(int $userId): int
    {
        return $this->messages()
            ->where('sender_id', '!=', $userId)
            ->where('id', '>', $this->lastReadId($userId))
            ->count();
    }

    // ไฟล์รูปในทุกห้องของผู้ใช้ (ใช้ตอนลบบัญชี ก่อนห้องถูกลบตาม cascade)
    public static function mediaPathsOf(int $userId): array
    {
        return ChatMessage::whereIn('conversation_id', self::of($userId)->select('id'))
            ->whereNotNull('image_path')
            ->pluck('image_path')
            ->all();
    }
}
