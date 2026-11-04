<?php

namespace App\Filament\Resources\MarketFlags;

use App\Filament\Resources\MarketFlags\Pages\ListMarketFlags;
use App\Filament\Resources\MarketFlags\Tables\MarketFlagsTable;
use App\Models\MarketFlag;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// สินค้า/ร้านที่ระบบตรวจพบว่าอาจผิดกฎหมาย
// ซ่อนสินค้า / ระงับร้าน / ไม่ผิดกฎ (คำเดิมไม่แจ้งซ้ำ)
// =======================================================

class MarketFlagResource extends Resource
{
    protected static ?string $model = MarketFlag::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedShieldExclamation;

    protected static ?string $modelLabel = 'รายการตรวจพบ';

    protected static ?string $pluralModelLabel = 'ตรวจพบสินค้าต้องห้าม';

    protected static ?string $navigationLabel = 'ตรวจพบสินค้าต้องห้าม';

    protected static ?int $navigationSort = 2;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()->with(['flaggable', 'shop:id,name,status,user_id', 'shop.owner:id,name,email']);
    }

    // ตัวเลขบนเมนู = รายการที่ยังไม่ได้ตรวจ
    public static function getNavigationBadge(): ?string
    {
        $count = MarketFlag::open()->count();

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
        return MarketFlagsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListMarketFlags::route('/'),
        ];
    }
}
