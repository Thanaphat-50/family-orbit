<?php

namespace App\Support;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Throwable;

// =======================================================
// ที่เก็บไฟล์รูป (รูปโปรไฟล์ / รูปในโพสต์)
// - ในเครื่อง: disk public + URL ตรง
// - บน Cloud: Default Disk ที่เชื่อมกับ Private Bucket
//             + ลิงก์ชั่วคราว 12 ชม.
// =======================================================

class MediaStorage
{
    public static function disk(): string
    {
        $default = config(
            'filesystems.default',
            'local'
        );

        return $default === 'local'
            ? 'public'
            : $default;
    }

    public static function url(?string $path): ?string
    {
        if (!$path) {
            return null;
        }

        $disk = self::disk();

        // สำหรับการพัฒนาในเครื่อง
        if ($disk === 'public') {
            return request()->getSchemeAndHttpHost()
                . '/storage/'
                . ltrim($path, '/');
        }

        // สำหรับ Private Bucket บน Cloud
        try {
            return Storage::disk($disk)->temporaryUrl(
                $path,
                now()->addHours(12)
            );
        } catch (Throwable $e) {
            Log::warning('Cannot generate media URL', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    // ลบไฟล์ (ลบไม่สำเร็จแค่บันทึก Log ไม่ให้งานหลักล้ม)
    public static function delete(array $paths): void
    {
        $paths = array_values(array_filter($paths));

        if ($paths === []) {
            return;
        }

        try {
            Storage::disk(self::disk())->delete($paths);
        } catch (Throwable $e) {
            Log::warning('Could not delete media files', [
                'count' => count($paths),
                'error' => $e->getMessage(),
            ]);
        }
    }
}
