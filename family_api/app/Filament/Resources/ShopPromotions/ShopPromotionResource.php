<?php

namespace App\Filament\Resources\ShopPromotions;

use App\Filament\Resources\ShopPromotions\Pages\ListShopPromotions;
use App\Filament\Resources\ShopPromotions\Tables\ShopPromotionsTable;
use App\Models\ShopPromotion;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// ช่องร้านแนะนำ (แบนเนอร์ใหญ่): ตรวจสลิปพร้อมเพย์ → อนุมัติ / ไม่ผ่าน
// =======================================================

class ShopPromotionResource extends Resource
{
    protected static ?string $model = ShopPromotion::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedBuildingStorefront;

    protected static ?string $modelLabel = 'ร้านแนะนำ';

    protected static ?string $pluralModelLabel = 'ร้านแนะนำ (ชำระเงิน)';

    protected static ?string $navigationLabel = 'ร้านแนะนำ (ชำระเงิน)';

    protected static ?int $navigationSort = 4;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()
            ->with(['shop:id,name,featured_until,status', 'user:id,name,email']);
    }

    // ตัวเลขบนเมนู = สลิปที่รอตรวจ
    public static function getNavigationBadge(): ?string
    {
        $count = ShopPromotion::where('status', ShopPromotion::STATUS_PENDING_REVIEW)->count();

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
        return ShopPromotionsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListShopPromotions::route('/'),
        ];
    }
}
