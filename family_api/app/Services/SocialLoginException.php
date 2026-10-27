<?php

namespace App\Services;

use RuntimeException;

// ตรวจการเข้าสู่ระบบด้วย Google / LINE / Facebook ไม่ผ่าน (ข้อความแสดงให้ผู้ใช้)
class SocialLoginException extends RuntimeException
{
}
