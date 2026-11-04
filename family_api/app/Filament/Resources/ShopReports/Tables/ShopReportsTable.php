<?php

namespace App\Filament\Resources\ShopReports\Tables;

use App\Models\Shop;
use App\Models\ShopReport;
use Filament\Actions\Action;
use Filament\Forms\Components\Textarea;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;

class ShopReportsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                TextColumn::make('shop.name')
                    ->label('ร้าน')
                    ->description(fn (ShopReport $record) => $record->shop?->owner?->email)
                    ->searchable(),
                TextColumn::make('shop.status')
                    ->label('สถานะร้าน')
                    ->formatStateUsing(fn (?string $state) => Shop::STATUS_LABELS[$state] ?? '-')
                    ->description(fn (ShopReport $record) => $record->shop?->status === Shop::STATUS_SUSPENDED
                        ? $record->shop->status_reason
                        : null)
                    ->badge()
                    ->color(fn (?string $state) => $state === Shop::STATUS_ACTIVE ? 'success' : 'danger'),
                TextColumn::make('reason')
                    ->label('เหตุผล')
                    ->formatStateUsing(fn (string $state) => config('market.report_reasons')[$state] ?? $state)
                    ->badge()
                    ->color('danger'),
                TextColumn::make('details')
                    ->label('รายละเอียด')
                    ->placeholder('-')
                    ->wrap()
                    ->limit(300),
                TextColumn::make('user.name')
                    ->label('ผู้รายงาน')
                    ->description(fn (ShopReport $record) => $record->user?->email),
                TextColumn::make('created_at')
                    ->label('เมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->recordActions([
                Action::make('suspend')
                    ->label('ระงับร้าน')
                    ->icon(Heroicon::OutlinedNoSymbol)
                    ->color('danger')
                    ->visible(fn (ShopReport $record) => $record->shop?->status === Shop::STATUS_ACTIVE)
                    ->schema([
                        Textarea::make('reason')
                            ->label('เหตุผล (เจ้าของร้านจะเห็นข้อความนี้)')
                            ->required()
                            ->maxLength(500),
                    ])
                    ->action(fn (ShopReport $record, array $data) => $record->shop->suspend($data['reason'])),
                // ร้านที่ระบบปิดเพราะถูกรายงาน → ตรวจแล้วไม่ผิด เปิดคืน + ล้างรายงานของร้านนี้
                Action::make('reopen')
                    ->label('ไม่ผิดกฎ เปิดร้านคืน')
                    ->icon(Heroicon::OutlinedCheckCircle)
                    ->color('success')
                    ->requiresConfirmation()
                    ->visible(fn (ShopReport $record) => $record->shop?->status === Shop::STATUS_SUSPENDED
                        && $record->shop->status_reason === Shop::AUTO_REPORT_REASON)
                    ->action(function (ShopReport $record) {
                        $shop = $record->shop;

                        $shop->reports()->delete();
                        $shop->approve();
                    }),
                // รายงานไม่มีมูล → ลบรายงานนี้
                Action::make('delete')
                    ->label('ลบรายงาน')
                    ->icon(Heroicon::OutlinedTrash)
                    ->color('gray')
                    ->requiresConfirmation()
                    ->action(fn (ShopReport $record) => $record->delete()),
            ])
            ->filters([
                SelectFilter::make('reason')
                    ->label('เหตุผล')
                    ->options(config('market.report_reasons')),
            ]);
    }
}
