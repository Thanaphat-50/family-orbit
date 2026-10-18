<?php

namespace App\Filament\Resources\Products;

use App\Filament\Resources\Products\Pages\ListProducts;
use App\Filament\Resources\Products\Tables\ProductsTable;
use App\Models\Product;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// สินค้าในตลาด: ตรวจรายงาน ซ่อน / คืน / ลบ
// =======================================================

class ProductResource extends Resource
{
    protected static ?string $model = Product::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedShoppingBag;

    protected static ?string $modelLabel = 'สินค้า';

    protected static ?string $pluralModelLabel = 'สินค้าในตลาด';

    protected static ?string $navigationLabel = 'สินค้าในตลาด';

    protected static ?int $navigationSort = 4;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()
            ->with('shop:id,name,user_id')
            ->withCount('reports');
    }

    // ตัวเลขบนเมนู = สินค้าที่ถูกรายงานแต่ยังไม่ถูกซ่อน (รอตรวจ)
    public static function getNavigationBadge(): ?string
    {
        $count = Product::whereNull('hidden_at')->has('reports')->count();

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
        return ProductsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListProducts::route('/'),
        ];
    }
}
