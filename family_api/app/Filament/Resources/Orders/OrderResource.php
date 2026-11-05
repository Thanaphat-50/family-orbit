<?php

namespace App\Filament\Resources\Orders;

use App\Filament\Resources\Orders\Pages\ListOrders;
use App\Filament\Resources\Orders\Tables\OrdersTable;
use App\Models\Order;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// คำสั่งซื้อในตลาด (ดูอย่างเดียว ใช้ตรวจสอบเมื่อมีปัญหาระหว่างผู้ซื้อกับร้าน)
// เงินโอนเข้าร้านโดยตรง แอปไม่ได้ถือเงิน
// =======================================================

class OrderResource extends Resource
{
    protected static ?string $model = Order::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedShoppingBag;

    protected static ?string $modelLabel = 'คำสั่งซื้อ';

    protected static ?string $pluralModelLabel = 'คำสั่งซื้อ';

    protected static ?string $navigationLabel = 'คำสั่งซื้อ';

    protected static ?int $navigationSort = 5;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()->with(['shop:id,name', 'buyer:id,name,email']);
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function table(Table $table): Table
    {
        return OrdersTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListOrders::route('/'),
        ];
    }
}
