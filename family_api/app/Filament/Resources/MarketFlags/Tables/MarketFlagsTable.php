<?php

namespace App\Filament\Resources\MarketFlags\Tables;

use App\Models\MarketFlag;
use App\Models\Product;
use App\Models\Shop;
use Filament\Actions\Action;
use Filament\Forms\Components\Textarea;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Auth;

class MarketFlagsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                TextColumn::make('flaggable_type')
                    ->label('ประเภท')
                    ->formatStateUsing(fn (string $state) => $state === Product::class ? 'สินค้า' : 'ร้าน')
                    ->badge()
                    ->color(fn (string $state) => $state === Product::class ? 'info' : 'warning'),
                TextColumn::make('item')
                    ->label('ชื่อ')
                    ->state(fn (MarketFlag $record) => $record->itemName())
                    ->description(fn (MarketFlag $record) => $record->excerpt)
                    ->wrap(),
                TextColumn::make('shop.name')
                    ->label('ร้าน')
                    ->description(fn (MarketFlag $record) => $record->shop?->owner?->email)
                    ->searchable(),
                TextColumn::make('categories')
                    ->label('เข้าข่าย')
                    ->state(fn (MarketFlag $record) => $record->categoryLabels())
                    ->badge()
                    ->color('danger')
                    ->wrap(),
                TextColumn::make('terms')
                    ->label('คำที่พบ')
                    ->state(fn (MarketFlag $record) => implode(', ', $record->terms ?? [])),
                TextColumn::make('auto_hidden')
                    ->label('ระบบซ่อนไว้')
                    ->formatStateUsing(fn (bool $state, MarketFlag $record) => $state
                        ? ($record->isProduct() ? 'ซ่อนสินค้าแล้ว' : 'ปิดร้านแล้ว')
                        : '-')
                    ->badge()
                    ->color(fn (bool $state) => $state ? 'warning' : 'gray'),
                TextColumn::make('status')
                    ->label('สถานะ')
                    ->formatStateUsing(fn (string $state) => MarketFlag::STATUS_LABELS[$state] ?? $state)
                    ->badge()
                    ->color(fn (string $state) => match ($state) {
                        MarketFlag::STATUS_OPEN => 'danger',
                        MarketFlag::STATUS_ACTIONED => 'success',
                        default => 'gray',
                    }),
                TextColumn::make('created_at')
                    ->label('ตรวจพบเมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->recordActions([
                // ระบบซ่อน/ปิดไว้แล้ว และผิดกฎจริง → ปิดรายการ (ยังซ่อนต่อ)
                Action::make('confirm')
                    ->label('ผิดกฎจริง')
                    ->icon(Heroicon::OutlinedShieldExclamation)
                    ->color('danger')
                    ->requiresConfirmation()
                    ->modalDescription('สินค้า/ร้านจะถูกซ่อนต่อไป')
                    ->visible(fn (MarketFlag $record) => $record->status === MarketFlag::STATUS_OPEN && $record->auto_hidden)
                    ->action(fn (MarketFlag $record) => $record->close(Auth::user(), MarketFlag::STATUS_ACTIONED)),
                // สินค้าผิดกฎ → ซ่อนจากหน้าร้านค้า (เหมือนปุ่มซ่อนในหน้าสินค้า)
                Action::make('hideProduct')
                    ->label('ซ่อนสินค้า')
                    ->icon(Heroicon::OutlinedEyeSlash)
                    ->color('danger')
                    ->requiresConfirmation()
                    ->visible(fn (MarketFlag $record) => $record->status === MarketFlag::STATUS_OPEN
                        && $record->flaggable instanceof Product
                        && $record->flaggable->hidden_at === null)
                    ->action(function (MarketFlag $record) {
                        $record->flaggable->forceFill(['hidden_at' => now()])->save();

                        $record->close(Auth::user(), MarketFlag::STATUS_ACTIONED);
                    }),
                Action::make('suspendShop')
                    ->label('ระงับร้าน')
                    ->icon(Heroicon::OutlinedNoSymbol)
                    ->color('danger')
                    ->visible(fn (MarketFlag $record) => $record->status === MarketFlag::STATUS_OPEN
                        && $record->shop?->status === Shop::STATUS_ACTIVE)
                    ->schema([
                        Textarea::make('reason')
                            ->label('เหตุผล (เจ้าของร้านจะเห็นข้อความนี้)')
                            ->default('ขายสินค้าต้องห้ามตามกฎผู้ขาย')
                            ->required()
                            ->maxLength(500),
                    ])
                    ->action(function (MarketFlag $record, array $data) {
                        $record->shop->suspend($data['reason']);

                        $record->close(Auth::user(), MarketFlag::STATUS_ACTIONED);
                    }),
                // ตรวจแล้วไม่ผิดกฎ (เช่น ร้านชื่อ "น้องเบียร์") → แสดงคืน + คำเดิมจะไม่แจ้งซ้ำ
                Action::make('dismiss')
                    ->label('ไม่ผิดกฎ')
                    ->icon(Heroicon::OutlinedCheckCircle)
                    ->color('success')
                    ->requiresConfirmation()
                    ->modalDescription(fn (MarketFlag $record) => $record->auto_hidden
                        ? 'สินค้า/ร้านจะกลับมาแสดงตามปกติ และแจ้งเจ้าของร้าน'
                        : null)
                    ->visible(fn (MarketFlag $record) => $record->status === MarketFlag::STATUS_OPEN)
                    ->action(fn (MarketFlag $record) => $record->dismiss(Auth::user())),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('สถานะ')
                    ->options(MarketFlag::STATUS_LABELS)
                    ->default(MarketFlag::STATUS_OPEN),
            ]);
    }
}
