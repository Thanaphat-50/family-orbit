<?php

namespace App\Filament\Resources\ShopPromotions\Tables;

use App\Models\ShopPromotion;
use App\Support\MediaStorage;
use Filament\Actions\Action;
use Filament\Forms\Components\Textarea;
use Filament\Notifications\Notification;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\ImageColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Auth;

class ShopPromotionsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                // กดรูปเพื่อดูสลิปขนาดเต็ม
                ImageColumn::make('slip_path')
                    ->label('สลิป')
                    ->disk(MediaStorage::disk())
                    ->visibility('private')
                    ->checkFileExistence(false)
                    ->imageHeight(64)
                    ->url(fn (ShopPromotion $record) => $record->slip_url, shouldOpenInNewTab: true),
                TextColumn::make('shop.name')
                    ->label('ร้าน')
                    ->wrap()
                    ->searchable(),
                TextColumn::make('user.name')
                    ->label('ผู้ขาย')
                    ->description(fn (ShopPromotion $record) => $record->user?->email)
                    ->searchable(),
                TextColumn::make('plan')
                    ->label('แพ็กเกจ')
                    ->formatStateUsing(fn (string $state, ShopPromotion $record) => (config('market.shop_promotion_plans')[$state]['label'] ?? $state) . ' (' . $record->days . ' วัน)'),
                TextColumn::make('amount')
                    ->label('ยอดที่ต้องโอน')
                    ->money('THB')
                    ->sortable(),
                TextColumn::make('status')
                    ->label('สถานะ')
                    ->formatStateUsing(fn (string $state) => ShopPromotion::STATUS_LABELS[$state] ?? $state)
                    ->description(fn (ShopPromotion $record) => $record->reject_reason)
                    ->badge()
                    ->color(fn (string $state) => match ($state) {
                        ShopPromotion::STATUS_APPROVED => 'success',
                        ShopPromotion::STATUS_PENDING_REVIEW => 'warning',
                        ShopPromotion::STATUS_AWAITING_PAYMENT => 'gray',
                        default => 'danger',
                    }),
                TextColumn::make('ends_at')
                    ->label('แนะนำถึง')
                    ->dateTime('d/m/Y H:i', config('market.timezone'))
                    ->placeholder('-'),
                TextColumn::make('slip_uploaded_at')
                    ->label('แนบสลิปเมื่อ')
                    ->since()
                    ->placeholder('-')
                    ->sortable(),
            ])
            ->recordActions([
                // ตรวจยอดและบัญชีปลายทางในสลิปแล้ว → สินค้าขึ้นช่องแนะนำทันที
                Action::make('approve')
                    ->label('อนุมัติ')
                    ->icon(Heroicon::OutlinedCheckCircle)
                    ->color('success')
                    ->requiresConfirmation()
                    ->modalDescription(fn (ShopPromotion $record) => 'ตรวจแล้วว่าสลิปโอนเข้าบัญชีพร้อมเพย์ของแอป ยอด '
                        . number_format((float) $record->amount, 2) . ' บาท')
                    ->visible(fn (ShopPromotion $record) => $record->status === ShopPromotion::STATUS_PENDING_REVIEW)
                    ->action(function (ShopPromotion $record, Action $action) {
                        $shop = $record->shop;

                        if (!$shop) {
                            Notification::make()->title('ไม่พบร้านนี้แล้ว')->danger()->send();
                            $action->halt();
                        }

                        $slots = ShopPromotion::slots();

                        // ช่องของร้านอื่นเต็มแล้ว (ต่ออายุร้านที่แนะนำอยู่ไม่ใช้ช่องเพิ่ม)
                        if (!$shop->isFeatured() && ShopPromotion::usedSlots($shop->id) >= $slots) {
                            Notification::make()
                                ->title("ช่องร้านแนะนำเต็มแล้ว ({$slots} ช่อง)")
                                ->body('เพิ่มจำนวนใน MARKET_FEATURED_SLOTS หรือกด "ไม่ผ่าน" แล้วคืนเงินให้ร้าน')
                                ->danger()
                                ->send();
                            $action->halt();
                        }

                        $record->approve(Auth::user());
                    }),
                Action::make('reject')
                    ->label('ไม่ผ่าน')
                    ->icon(Heroicon::OutlinedXCircle)
                    ->color('danger')
                    ->visible(fn (ShopPromotion $record) => $record->status === ShopPromotion::STATUS_PENDING_REVIEW)
                    ->schema([
                        Textarea::make('reason')
                            ->label('เหตุผล (ผู้ขายจะเห็นข้อความนี้)')
                            ->placeholder('เช่น ยอดเงินไม่ตรง / ไม่พบรายการโอน')
                            ->required()
                            ->maxLength(300),
                    ])
                    ->action(fn (ShopPromotion $record, array $data) => $record->reject(Auth::user(), $data['reason'])),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('สถานะ')
                    ->options(ShopPromotion::STATUS_LABELS)
                    ->default(ShopPromotion::STATUS_PENDING_REVIEW),
            ]);
    }
}
