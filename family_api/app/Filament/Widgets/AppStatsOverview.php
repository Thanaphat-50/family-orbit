<?php

namespace App\Filament\Widgets;

use App\Models\Comment;
use App\Models\Family;
use App\Models\Post;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

// =======================================================
// Dashboard: ตัวเลขภาพรวมของแอป
// =======================================================

class AppStatsOverview extends StatsOverviewWidget
{
    protected static ?int $sort = 1;

    protected function getStats(): array
    {
        // โพสต์ + ความคิดเห็น ที่ถูกรายงานแต่ยังไม่ถูกซ่อน
        $pendingReports = Post::where('visibility', 'community')
            ->whereNull('hidden_at')
            ->has('reports')
            ->count()
            + Comment::whereNull('hidden_at')
                ->has('reports')
                ->count()
            + Product::whereNull('hidden_at')
                ->has('reports')
                ->count()
            + Shop::has('reports')->count();

        $pendingShops = Shop::where('status', Shop::STATUS_PENDING)->count();

        return [
            Stat::make('ผู้ใช้ทั้งหมด', User::count())
                ->description('สมัครใหม่ 7 วันล่าสุด: ' . User::where('created_at', '>=', now()->subDays(7))->count()),

            Stat::make('ครอบครัว', Family::count()),

            Stat::make('โพสต์ชุมชน', Post::where('visibility', 'community')->count()),

            Stat::make('รายงานรอตรวจ', $pendingReports)
                ->description($pendingReports > 0 ? 'ดูที่เมนูชุมชนและตลาดที่มีตัวเลขสีแดง' : 'ไม่มีรายงานค้าง')
                ->color($pendingReports > 0 ? 'danger' : 'success'),

            Stat::make('ร้านรออนุมัติ', $pendingShops)
                ->description(
                    'เปิดขายอยู่: ' . Shop::where('status', Shop::STATUS_ACTIVE)->count() . ' ร้าน · '
                        . 'ร้านแนะนำ: ' . Shop::featured()->count() . '/' . (int) config('market.featured_slots')
                )
                ->color($pendingShops > 0 ? 'warning' : 'success'),
        ];
    }
}
