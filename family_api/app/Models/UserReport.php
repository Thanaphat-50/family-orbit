<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserReport extends Model
{
    // เหตุผลที่เลือกได้ (แอปใช้ key ชุดเดียวกัน)
    public const REASONS = [
        'spam' => 'สแปม / โฆษณา',
        'harassment' => 'ด่าทอ / คุกคาม',
        'inappropriate' => 'เนื้อหาไม่เหมาะสม',
        'scam' => 'หลอกลวง / ข้อมูลเท็จ',
        'impersonation' => 'แอบอ้างเป็นคนอื่น',
        'other' => 'อื่น ๆ',
    ];

    protected $fillable = [
        'reported_user_id',
        'user_id',
        'reason',
        'details',
    ];

    public function reportedUser()
    {
        return $this->belongsTo(User::class, 'reported_user_id');
    }

    // ผู้รายงาน
    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
