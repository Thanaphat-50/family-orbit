<?php

namespace Tests\Concerns;

use Illuminate\Http\UploadedFile;

trait FakesImages
{
    // =====================================================
    // รูป PNG ขนาด 1x1 สำหรับทดสอบอัปโหลด
    // (เครื่องที่ไม่มี GD ก็ใช้ได้)
    // =====================================================

    protected function fakePng(string $name = 'photo.png'): UploadedFile
    {
        return UploadedFile::fake()->createWithContent(
            $name,
            base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
        );
    }
}
