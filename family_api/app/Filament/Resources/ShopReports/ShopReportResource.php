<?php

namespace App\Filament\Resources\ShopReports;

use App\Filament\Resources\ShopReports\Pages\ListShopReports;
use App\Filament\Resources\ShopReports\Tables\ShopReportsTable;
use App\Models\ShopReport;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// รายงานร้านค้าจากผู้ใช้: ดูเหตุผล → ระงับร้าน / ลบรายงาน
// =======================================================

class ShopReportResource extends Resource
{
    protected static ?string $model = ShopReport::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedFlag;

    protected static ?string $modelLabel = 'รายงานร้านค้า';

    protected static ?string $pluralModelLabel = 'รายงานร้านค้า';

    protected static ?string $navigationLabel = 'รายงานร้านค้า';

    protected static ?int $navigationSort = 3;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()
            ->with(['shop:id,name,status,status_reason,user_id', 'shop.owner:id,name,email', 'user:id,name,email']);
    }

    // ตัวเลขบนเมนู = รายงานของร้านที่ยังเปิดขายอยู่ (ร้านที่ปิดแล้วไม่นับ)
    public static function getNavigationBadge(): ?string
    {
        $count = ShopReport::whereHas('shop', fn (Builder $shops) => $shops->active())->count();

        return $count > 0 ? (string) $count : null;
    }

    public static function getNavigationBadgeColor(): ?string
    {
        return 'danger';
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function table(Table $table): Table
    {
        return ShopReportsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListShopReports::route('/'),
        ];
    }
}
