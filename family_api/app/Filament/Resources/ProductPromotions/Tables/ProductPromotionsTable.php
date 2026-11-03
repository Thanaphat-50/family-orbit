<?php

namespace App\Filament\Resources\ProductPromotions\Tables;

use App\Models\ProductPromotion;
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

class ProductPromotionsTable
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
                    ->url(fn (ProductPromotion $record) => $record->slip_url, shouldOpenInNewTab: true),
                TextColumn::make('product.title')
                    ->label('สินค้า')
                    ->description(fn (ProductPromotion $record) => $record->product?->shop?->name)
                    ->wrap()
                    ->searchable(),
                TextColumn::make('user.name')
                    ->label('ผู้ขาย')
                    ->description(fn (ProductPromotion $record) => $record->user?->email)
                    ->searchable(),
                TextColumn::make('category')
                    ->label('หมวด')
                    ->formatStateUsing(fn (string $state) => config('market.categories')[$state] ?? $state)
                    ->badge()
                    ->color('info'),
                TextColumn::make('plan')
                    ->label('แพ็กเกจ')
                    ->formatStateUsing(fn (string $state, ProductPromotion $record) => (config('market.promotion_plans')[$state]['label'] ?? $state) . ' (' . $record->days . ' วัน)'),
                TextColumn::make('amount')
                    ->label('ยอดที่ต้องโอน')
                    ->money('THB')
                    ->sortable(),
                TextColumn::make('status')
                    ->label('สถานะ')
                    ->formatStateUsing(fn (string $state) => ProductPromotion::STATUS_LABELS[$state] ?? $state)
                    ->description(fn (ProductPromotion $record) => $record->reject_reason)
                    ->badge()
                    ->color(fn (string $state) => match ($state) {
                        ProductPromotion::STATUS_APPROVED => 'success',
                        ProductPromotion::STATUS_PENDING_REVIEW => 'warning',
                        ProductPromotion::STATUS_AWAITING_PAYMENT => 'gray',
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
                    ->modalDescription(fn (ProductPromotion $record) => 'ตรวจแล้วว่าสลิปโอนเข้าบัญชีพร้อมเพย์ของแอป ยอด '
                        . number_format((float) $record->amount, 2) . ' บาท')
                    ->visible(fn (ProductPromotion $record) => $record->status === ProductPromotion::STATUS_PENDING_REVIEW)
                    ->action(function (ProductPromotion $record, Action $action) {
                        $product = $record->product;

                        if (!$product) {
                            Notification::make()->title('ไม่พบสินค้านี้แล้ว')->danger()->send();
                            $action->halt();
                        }

                        $slots = ProductPromotion::slotsPerCategory();

                        // ช่องของสินค้าอื่นเต็มแล้ว (ต่ออายุสินค้าที่แนะนำอยู่ไม่ใช้ช่องเพิ่ม)
                        if (!$product->isFeatured() && ProductPromotion::usedSlots($product->category, $product->id) >= $slots) {
                            Notification::make()
                                ->title("ช่องแนะนำหมวดนี้เต็มแล้ว ({$slots} ช่อง)")
                                ->body('เพิ่มจำนวนใน MARKET_FEATURED_SLOTS_PER_CATEGORY หรือกด "ไม่ผ่าน" แล้วคืนเงินให้ผู้ขาย')
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
                    ->visible(fn (ProductPromotion $record) => $record->status === ProductPromotion::STATUS_PENDING_REVIEW)
                    ->schema([
                        Textarea::make('reason')
                            ->label('เหตุผล (ผู้ขายจะเห็นข้อความนี้)')
                            ->placeholder('เช่น ยอดเงินไม่ตรง / ไม่พบรายการโอน')
                            ->required()
                            ->maxLength(300),
                    ])
                    ->action(fn (ProductPromotion $record, array $data) => $record->reject(Auth::user(), $data['reason'])),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('สถานะ')
                    ->options(ProductPromotion::STATUS_LABELS)
                    ->default(ProductPromotion::STATUS_PENDING_REVIEW),
                SelectFilter::make('category')
                    ->label('หมวด')
                    ->options(config('market.categories')),
            ]);
    }
}
