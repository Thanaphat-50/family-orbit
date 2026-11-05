<?php

namespace App\Filament\Resources\Orders\Tables;

use App\Models\Order;
use App\Support\MediaStorage;
use Filament\Tables\Columns\ImageColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;

class OrdersTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                TextColumn::make('code')
                    ->label('เลขที่')
                    ->searchable(),
                TextColumn::make('product_title')
                    ->label('สินค้า')
                    ->description(fn (Order $record) => $record->shop?->name)
                    ->wrap()
                    ->searchable(),
                TextColumn::make('buyer.name')
                    ->label('ผู้ซื้อ')
                    ->description(fn (Order $record) => $record->buyer?->email)
                    ->searchable(),
                TextColumn::make('total')
                    ->label('ยอดรวม')
                    ->formatStateUsing(fn ($state, Order $record) => Order::baht($state) . " ({$record->quantity} ชิ้น)")
                    ->sortable(),
                TextColumn::make('payment_method')
                    ->label('ชำระเงิน')
                    ->formatStateUsing(fn (string $state) => config("market.payment_methods.{$state}.label", $state))
                    ->description(fn (Order $record) => config("market.delivery_methods.{$record->delivery_method}")),
                // กดรูปเพื่อดูสลิปขนาดเต็ม
                ImageColumn::make('slip_path')
                    ->label('สลิป')
                    ->disk(MediaStorage::disk())
                    ->visibility('private')
                    ->checkFileExistence(false)
                    ->imageHeight(48)
                    ->url(fn (Order $record) => $record->slip_url, shouldOpenInNewTab: true),
                TextColumn::make('status')
                    ->label('สถานะ')
                    ->formatStateUsing(fn (string $state, Order $record) => $record->statusLabel())
                    ->description(fn (Order $record) => $record->cancel_reason)
                    ->badge()
                    ->color(fn (string $state) => match ($state) {
                        Order::STATUS_COMPLETED => 'success',
                        Order::STATUS_CANCELLED => 'danger',
                        Order::STATUS_AWAITING_PAYMENT => 'warning',
                        default => 'info',
                    }),
                TextColumn::make('created_at')
                    ->label('สั่งเมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('สถานะ')
                    ->options(Order::STATUS_LABELS),
            ]);
    }
}
