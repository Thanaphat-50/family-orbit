<?php

namespace App\Filament\Resources\Shops;

use App\Filament\Resources\Shops\Pages\ListShops;
use App\Filament\Resources\Shops\Tables\ShopsTable;
use App\Models\Shop;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// ร้านค้าในตลาด: อนุมัติ / ไม่ผ่าน / ระงับ
// =======================================================

class ShopResource extends Resource
{
    protected static ?string $model = Shop::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedBuildingStorefront;

    protected static ?string $modelLabel = 'ร้านค้า';

    protected static ?string $pluralModelLabel = 'ร้านค้า';

    protected static ?string $navigationLabel = 'ร้านค้า';

    protected static ?int $navigationSort = 3;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()
            ->with('owner:id,name,email')
            ->withCount('reports');
    }

    // ตัวเลขบนเมนู = ร้านที่รออนุมัติ
    public static function getNavigationBadge(): ?string
    {
        $count = Shop::where('status', Shop::STATUS_PENDING)->count();

        return $count > 0 ? (string) $count : null;
    }

    public static function getNavigationBadgeColor(): ?string
    {
        return 'warning';
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function table(Table $table): Table
    {
        return ShopsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListShops::route('/'),
        ];
    }
}
