<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// =======================================================
// แฮชแท็ก (#ทำอาหาร)
// - เก็บเป็นตัวพิมพ์เล็ก ไม่มี #
// - แอปใช้รูปแบบเดียวกันในการทำสีและกดลิงก์ (widgets/hashtag_text.dart)
// =======================================================

class Hashtag extends Model
{
    public const MAX_LENGTH = 50;

    // ต่อโพสต์
    public const MAX_PER_POST = 10;

    // # ที่อยู่ต้นข้อความหรือหลังช่องว่าง ตามด้วยตัวอักษร (รวมสระ/วรรณยุกต์ไทย) ตัวเลข หรือ _
    public const PATTERN = '/(?<!\S)#([\p{L}\p{M}\p{N}_]+)/u';

    protected $fillable = ['name'];

    public function posts()
    {
        return $this->belongsToMany(Post::class);
    }

    public static function normalize(string $tag): string
    {
        return mb_strtolower(ltrim(trim($tag), '#'));
    }

    // แท็กในข้อความ (ไม่ซ้ำ ไม่เกิน MAX_PER_POST)
    // ข้ามแท็กที่ยาวเกิน และแท็กที่มีแต่ตัวเลข เช่น #1
    public static function extract(string $content): array
    {
        preg_match_all(self::PATTERN, $content, $matches);

        return collect($matches[1] ?? [])
            ->map(fn (string $tag) => self::normalize($tag))
            ->filter(fn (string $tag) => mb_strlen($tag) <= self::MAX_LENGTH && !ctype_digit($tag))
            ->unique()
            ->take(self::MAX_PER_POST)
            ->values()
            ->all();
    }
}
