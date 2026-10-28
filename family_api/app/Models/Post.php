<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

class Post extends Model
{
    // หมวดหมู่ของโพสต์ชุมชน (โพสต์ครอบครัวไม่มีหมวด)
    public const CATEGORIES = [
        'general',
        'qa',
        'news',
        'help',
        'event',
    ];

    protected $fillable = [
        'family_id',
        'user_id',
        'visibility',
        'category',
        'content',
    ];

    // ข้อความบนแผนที่ (เช่น "ทำงานอยู่") แสดงข้างตำแหน่งของเจ้าของนานเท่านี้
    public const MAP_STATUS_HOURS = 12;

    protected $casts = [
        'hidden_at' => 'datetime',
        'map_status_until' => 'datetime',
    ];

    // on_map → แอปแสดงป้าย "บนแผนที่" และเมนูเอาออก
    protected $appends = [
        'on_map',
    ];

    public function getOnMapAttribute(): bool
    {
        // บาง Query เลือกเฉพาะบางคอลัมน์ → ไม่มีค่านี้ = ไม่ได้อยู่บนแผนที่
        $until = $this->getAttributes()['map_status_until'] ?? null;

        return $until !== null && $this->asDateTime($until)->isFuture();
    }

    // แสดงบนแผนที่ได้เฉพาะโพสต์ครอบครัวที่มีข้อความ
    public function canShowOnMap(): bool
    {
        return !$this->isCommunity() && trim((string) $this->content) !== '';
    }

    // แสดงบนแผนที่ แทนข้อความเดิมของเจ้าของ (คนละ 1 ข้อความ)
    public function showOnMap(): void
    {
        DB::transaction(function () {
            static::where('user_id', $this->user_id)
                ->whereKeyNot($this->getKey())
                ->whereNotNull('map_status_until')
                ->update(['map_status_until' => null]);

            $this->map_status_until = now()->addHours(self::MAP_STATUS_HOURS);

            $this->save();
        });
    }

    // ข้อความบนแผนที่ที่ยังไม่หมดเวลา
    public function scopeOnMap($query)
    {
        return $query->where('visibility', 'family')
            ->whereNull('hidden_at')
            ->where('map_status_until', '>', now());
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function family()
    {
        return $this->belongsTo(Family::class);
    }

    public function comments()
    {
        return $this->hasMany(Comment::class)->oldest();
    }

    public function reports()
    {
        return $this->hasMany(PostReport::class);
    }

    public function likes()
    {
        return $this->hasMany(PostLike::class);
    }

    public function images()
    {
        return $this->hasMany(PostImage::class)->orderBy('sort');
    }

    // ลบไฟล์รูปใน storage เมื่อโพสต์ถูกลบด้วย $post->delete()
    // (API ลบโพสต์ และปุ่มลบในหน้า Admin)
    //
    // โหลดรายการรูปไว้ก่อนลบ เพราะแถวใน post_images
    // จะถูกลบตามไปด้วย cascade และลบไฟล์หลัง Transaction สำเร็จ
    protected static function booted(): void
    {
        static::deleting(function (Post $post) {
            $post->loadMissing('images');
        });

        static::deleted(function (Post $post) {
            $paths = $post->images->pluck('path')->all();

            DB::afterCommit(fn () => MediaStorage::delete($paths));
        });
    }

    // โพสต์ที่ผู้ใช้ทุกคนในแอปเห็นได้
    public function isCommunity(): bool
    {
        return $this->visibility === 'community';
    }

    // โพสต์ชุมชนที่ $viewer เห็นได้
    // ไม่ถูกซ่อน, $viewer ยังไม่ได้รายงาน และไม่ใช่ของคนที่ $viewer บล็อก
    public function scopeVisibleInCommunityTo($query, User $viewer, $blockedIds = null)
    {
        $blockedIds ??= $viewer->blockedUsers()->pluck('users.id');

        return $query->where('visibility', 'community')
            ->whereNull('hidden_at')
            ->whereDoesntHave('reports', function ($reports) use ($viewer) {
                $reports->where('user_id', $viewer->id);
            })
            ->whereNotIn('user_id', $blockedIds);
    }

    // โพสต์ที่ $viewer เห็นได้ในหน้าโปรไฟล์ของคนอื่น
    // โพสต์ชุมชนที่ $viewer เห็นได้ + โพสต์ครอบครัวในครอบครัวของ $viewer
    public function scopeVisibleOnProfileTo($query, User $viewer, ?int $viewerFamilyId, $blockedIds = null)
    {
        return $query->where(function ($posts) use ($viewer, $viewerFamilyId, $blockedIds) {
            $posts->where(function ($community) use ($viewer, $blockedIds) {
                $community->visibleInCommunityTo($viewer, $blockedIds);
            });

            if ($viewerFamilyId) {
                $posts->orWhere(function ($family) use ($viewerFamilyId) {
                    $family->where('visibility', 'family')
                        ->where('family_id', $viewerFamilyId);
                });
            }
        });
    }
}
