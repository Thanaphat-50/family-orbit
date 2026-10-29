<?php

namespace App\Support;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use RuntimeException;
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

    // เก็บไฟล์ที่อัปโหลดหลายไฟล์ลง storage
    // ถ้าล้มกลางทาง: ลบไฟล์ที่เก็บไปแล้วทิ้ง แล้วโยน Exception ต่อ
    public static function storeAll(array $files, string $directory): array
    {
        $paths = [];

        try {
            foreach ($files as $file) {
                $path = $file->store($directory, self::disk());

                if (!$path) {
                    throw new RuntimeException('Could not store the uploaded file.');
                }

                $paths[] = $path;
            }
        } catch (Throwable $e) {
            self::delete($paths);

            throw $e;
        }

        return $paths;
    }

    // ลิงก์ให้แอปอัปโหลดไฟล์ใหญ่ (วิดีโอ) ตรงเข้า Bucket
    // ไม่ผ่าน Server → ไม่ติดขนาดอัปโหลดของ PHP
    // ที่เก็บในเครื่อง (public) ทำไม่ได้ → null แอปส่งไฟล์มากับโพสต์แทน
    // @return array{url: string, headers: array}|null
    public static function uploadUrl(string $path, int $minutes = 30): ?array
    {
        if (self::disk() === 'public') {
            return null;
        }

        $storage = Storage::disk(self::disk());

        if (!$storage->providesTemporaryUploadUrls()) {
            return null;
        }

        try {
            return $storage->temporaryUploadUrl($path, now()->addMinutes($minutes));
        } catch (Throwable $e) {
            Log::warning('Cannot generate media upload URL', [
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
