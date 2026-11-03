<?php

namespace App\Filament\Resources\ProductPromotions;

use App\Filament\Resources\ProductPromotions\Pages\ListProductPromotions;
use App\Filament\Resources\ProductPromotions\Tables\ProductPromotionsTable;
use App\Models\ProductPromotion;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// ช่องแนะนำสินค้า: ตรวจสลิปพร้อมเพย์ → อนุมัติ / ไม่ผ่าน
// =======================================================

class ProductPromotionResource extends Resource
{
    protected static ?string $model = ProductPromotion::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedBanknotes;

    protected static ?string $modelLabel = 'ช่องแนะนำ';

    protected static ?string $pluralModelLabel = 'ช่องแนะนำ (ชำระเงิน)';

    protected static ?string $navigationLabel = 'ช่องแนะนำ (ชำระเงิน)';

    protected static ?int $navigationSort = 4;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()
            ->with(['product:id,title,category,featured_until,shop_id', 'product.shop:id,name', 'user:id,name,email']);
    }

    // ตัวเลขบนเมนู = สลิปที่รอตรวจ
    public static function getNavigationBadge(): ?string
    {
        $count = ProductPromotion::where('status', ProductPromotion::STATUS_PENDING_REVIEW)->count();

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
        return ProductPromotionsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListProductPromotions::route('/'),
        ];
    }
}
