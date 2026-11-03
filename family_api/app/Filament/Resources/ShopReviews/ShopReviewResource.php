<?php

namespace App\Filament\Resources\ShopReviews;

use App\Filament\Resources\ShopReviews\Pages\ListShopReviews;
use App\Filament\Resources\ShopReviews\Tables\ShopReviewsTable;
use App\Models\ShopReview;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// รีวิวร้าน: ซ่อนรีวิวที่ไม่เหมาะสม / สแปม
// =======================================================

class ShopReviewResource extends Resource
{
    protected static ?string $model = ShopReview::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedStar;

    protected static ?string $modelLabel = 'รีวิวร้าน';

    protected static ?string $pluralModelLabel = 'รีวิวร้าน';

    protected static ?string $navigationLabel = 'รีวิวร้าน';

    protected static ?int $navigationSort = 5;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()->with(['shop:id,name', 'user:id,name,email']);
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function table(Table $table): Table
    {
        return ShopReviewsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListShopReviews::route('/'),
        ];
    }
}
