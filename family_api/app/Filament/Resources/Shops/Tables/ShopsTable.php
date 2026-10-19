<?php

namespace App\Filament\Resources\Shops\Tables;

use App\Models\Shop;
use App\Support\MediaStorage;
use Filament\Actions\Action;
use Filament\Forms\Components\DatePicker;
use Filament\Forms\Components\Textarea;
use Filament\Notifications\Notification;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\ImageColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;

class ShopsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                ImageColumn::make('logo_path')
                    ->label('โลโก้')
                    ->disk(MediaStorage::disk())
                    ->visibility('private')
                    ->checkFileExistence(false)
                    ->circular(),

                TextColumn::make('name')
                    ->label('ชื่อร้าน')
                    ->description(fn (Shop $record) => $record->description)
                    ->wrap()
                    ->searchable(),

                TextColumn::make('owner.name')
                    ->label('เจ้าของ')
                    ->description(fn (Shop $record) => $record->owner?->email)
                    ->searchable(),

                TextColumn::make('category')
                    ->label('หมวด')
                    ->formatStateUsing(fn (string $state) => config('market.categories')[$state] ?? $state)
                    ->badge()
                    ->color('info'),

                TextColumn::make('province')
                    ->label('พื้นที่')
                    ->description(fn (Shop $record) => $record->district)
                    ->searchable(),

                TextColumn::make('phone')
                    ->label('ติดต่อ')
                    ->description(fn (Shop $record) => $record->line_id ? 'LINE: ' . $record->line_id : null),

                TextColumn::make('reports_count')
                    ->label('รายงาน')
                    ->badge()
                    ->color(fn (int $state) => $state > 0 ? 'danger' : 'gray')
                    ->sortable(),

                TextColumn::make('status')
                    ->label('สถานะ')
                    ->formatStateUsing(fn (string $state) => Shop::STATUS_LABELS[$state] ?? $state)
                    ->description(fn (Shop $record) => $record->status_reason)
                    ->badge()
                    ->color(fn (string $state) => match ($state) {
                        Shop::STATUS_ACTIVE => 'success',
                        Shop::STATUS_PENDING => 'warning',
                        default => 'danger',
                    }),

                // ร้านแนะนำ: แสดงวันหมดอายุ (เลยวันแล้วเป็นสีเทา)
                TextColumn::make('featured_until')
                    ->label('แนะนำถึง')
                    ->date('d/m/Y', config('market.timezone'))
                    ->placeholder('-')
                    ->badge()
                    ->color(fn (Shop $record) => $record->isFeatured() ? 'warning' : 'gray')
                    ->sortable(),

                TextColumn::make('created_at')
                    ->label('สมัครเมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->recordActions([
                // ร้านที่เช่าพื้นที่ → ขึ้นแบนเนอร์ร้านแนะนำจนถึงวันที่เลือก
                Action::make('feature')
                    ->label(fn (Shop $record) => $record->isFeatured() ? 'ต่ออายุแนะนำ' : 'ตั้งร้านแนะนำ')
                    ->icon(Heroicon::OutlinedStar)
                    ->color('warning')
                    ->visible(fn (Shop $record) => $record->isActive())
                    ->schema([
                        DatePicker::make('until')
                            ->label('แสดงเป็นร้านแนะนำถึงวันที่')
                            ->required()
                            ->minDate(today()->addDay())
                            ->default(today()->addDays(30)),
                    ])
                    ->action(function (Shop $record, array $data, Action $action) {
                        $slots = (int) config('market.featured_slots');

                        $used = Shop::featured()->whereKeyNot($record->getKey())->count();

                        if ($used >= $slots) {
                            Notification::make()
                                ->title("ร้านแนะนำเต็มแล้ว ({$slots} ร้าน)")
                                ->body('ยกเลิกร้านแนะนำร้านอื่นก่อน หรือเพิ่มจำนวนใน MARKET_FEATURED_SLOTS')
                                ->danger()
                                ->send();

                            $action->halt();
                        }

                        $record->feature(
                            Carbon::parse($data['until'], config('market.timezone'))->endOfDay()
                        );
                    }),

                Action::make('unfeature')
                    ->label('ยกเลิกแนะนำ')
                    ->icon(Heroicon::OutlinedXMark)
                    ->color('gray')
                    ->requiresConfirmation()
                    ->visible(fn (Shop $record) => $record->isFeatured())
                    ->action(fn (Shop $record) => $record->unfeature()),

                // ตรวจแล้วผ่าน → เปิดขาย (ใช้คืนร้านที่ถูกระงับด้วย)
                Action::make('approve')
                    ->label(fn (Shop $record) => $record->status === Shop::STATUS_SUSPENDED ? 'เปิดร้านอีกครั้ง' : 'อนุมัติ')
                    ->icon(Heroicon::OutlinedCheckCircle)
                    ->color('success')
                    ->requiresConfirmation()
                    ->modalDescription('ร้านจะแสดงในตลาด และเจ้าของร้านจะได้รับแจ้งเตือน')
                    ->visible(fn (Shop $record) => $record->status !== Shop::STATUS_ACTIVE)
                    ->action(fn (Shop $record) => $record->approve()),

                Action::make('reject')
                    ->label('ไม่ผ่าน')
                    ->icon(Heroicon::OutlinedXCircle)
                    ->color('danger')
                    ->visible(fn (Shop $record) => $record->status === Shop::STATUS_PENDING)
                    ->schema([
                        Textarea::make('reason')
                            ->label('เหตุผล (เจ้าของร้านจะเห็นข้อความนี้)')
                            ->required()
                            ->maxLength(500),
                    ])
                    ->action(fn (Shop $record, array $data) => $record->reject($data['reason'])),

                Action::make('suspend')
                    ->label('ระงับ')
                    ->icon(Heroicon::OutlinedNoSymbol)
                    ->color('danger')
                    ->visible(fn (Shop $record) => $record->status === Shop::STATUS_ACTIVE)
                    ->schema([
                        Textarea::make('reason')
                            ->label('เหตุผล (เจ้าของร้านจะเห็นข้อความนี้)')
                            ->required()
                            ->maxLength(500),
                    ])
                    ->action(fn (Shop $record, array $data) => $record->suspend($data['reason'])),

                // ตรวจแล้วร้านไม่ผิดกฎ → ล้างรายงาน
                Action::make('dismissReports')
                    ->label('ล้างรายงาน')
                    ->icon(Heroicon::OutlinedCheckBadge)
                    ->color('gray')
                    ->requiresConfirmation()
                    ->visible(fn (Shop $record) => $record->reports_count > 0)
                    ->action(fn (Shop $record) => $record->reports()->delete()),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('สถานะ')
                    ->options(Shop::STATUS_LABELS),

                SelectFilter::make('category')
                    ->label('หมวด')
                    ->options(config('market.categories')),

                Filter::make('reported')
                    ->label('ถูกรายงาน')
                    ->query(fn (Builder $query) => $query->has('reports')),

                Filter::make('featured')
                    ->label('ร้านแนะนำ')
                    ->query(fn (Builder $query) => $query->featured()),
            ]);
    }
}
