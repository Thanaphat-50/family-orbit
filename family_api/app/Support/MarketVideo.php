<?php

namespace App\Support;

use Illuminate\Http\Request;
use Illuminate\Support\Str;
use RuntimeException;
use Throwable;

// =======================================================
// วิดีโอแนะนำร้าน/สินค้า (ไฟล์ video + รูปตัวอย่าง video_thumbnail)
// =======================================================

class MarketVideo
{
    public static function rules(): array
    {
        return [
            'video' => 'nullable|file|mimetypes:video/mp4,video/quicktime,video/3gpp|max:' . (int) config('market.video_max_kb'),
            'video_thumbnail' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:2048',
        ];
    }

    public static function messages(): array
    {
        return [
            'video.mimetypes' => 'รองรับเฉพาะวิดีโอ MP4',
            'video.max' => 'วิดีโอต้องมีขนาดไม่เกิน ' . intdiv((int) config('market.video_max_kb'), 1024) . ' MB',
            'video_thumbnail.*' => 'รูปตัวอย่างวิดีโอไม่ถูกต้อง',
        ];
    }

    // เก็บไฟล์ → ['video_path' => ..., 'video_thumbnail_path' => ...]
    // ล้มเหลว → ลบไฟล์ที่เก็บไปแล้วและโยน exception
    public static function store(Request $request, string $folder): array
    {
        $disk = MediaStorage::disk();

        $stored = [];

        try {
            $stored['video_path'] = $request->file('video')->storeAs(
                $folder,
                Str::uuid() . '.mp4',
                $disk
            ) ?: throw new RuntimeException('Could not store the video.');

            $stored['video_thumbnail_path'] = $request->hasFile('video_thumbnail')
                ? ($request->file('video_thumbnail')->store($folder . '/thumbnails', $disk)
                    ?: throw new RuntimeException('Could not store the thumbnail.'))
                : null;
        } catch (Throwable $e) {
            MediaStorage::delete(array_values($stored));

            throw $e;
        }

        return $stored;
    }
}
