<?php

namespace App\Filament\Resources\Products\Tables;

use App\Models\Product;
use App\Support\MediaStorage;
use Filament\Actions\Action;
use Filament\Actions\DeleteAction;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\ImageColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class ProductsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                ImageColumn::make('images.path')
                    ->label('รูป')
                    ->disk(MediaStorage::disk())
                    ->visibility('private')
                    ->checkFileExistence(false)
                    ->stacked()
                    ->limit(3)
                    ->limitedRemainingText(),

                TextColumn::make('title')
                    ->label('สินค้า')
                    ->description(fn (Product $record) => $record->description)
                    ->wrap()
                    ->searchable(),

                TextColumn::make('shop.name')
                    ->label('ร้าน')
                    ->searchable(),

                TextColumn::make('price')
                    ->label('ราคา')
                    ->formatStateUsing(fn ($state) => '฿' . number_format((float) $state, 2))
                    ->placeholder('สอบถามราคา'),

                TextColumn::make('category')
                    ->label('หมวด')
                    ->formatStateUsing(fn (string $state) => config('market.categories')[$state] ?? $state)
                    ->badge()
                    ->color('info'),

                TextColumn::make('reports_count')
                    ->label('รายงาน')
                    ->badge()
                    ->color(fn (int $state) => $state > 0 ? 'danger' : 'gray')
                    ->sortable(),

                TextColumn::make('visibility')
                    ->label('สถานะ')
                    ->state(fn (Product $record) => match (true) {
                        $record->hidden_at !== null => 'ซ่อนโดยผู้ดูแล',
                        $record->status === Product::STATUS_HIDDEN => 'ร้านซ่อนไว้',
                        default => 'แสดงอยู่',
                    })
                    ->badge()
                    ->color(fn (string $state) => match ($state) {
                        'แสดงอยู่' => 'success',
                        'ร้านซ่อนไว้' => 'gray',
                        default => 'warning',
                    }),

                TextColumn::make('views')
                    ->label('เข้าชม')
                    ->sortable(),

                TextColumn::make('created_at')
                    ->label('ลงเมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->filters([
                Filter::make('reported')
                    ->label('ถูกรายงาน')
                    ->query(fn (Builder $query) => $query->has('reports')),

                SelectFilter::make('category')
                    ->label('หมวด')
                    ->options(config('market.categories')),

                TernaryFilter::make('hidden_at')
                    ->label('ซ่อนโดยผู้ดูแล')
                    ->nullable()
                    ->trueLabel('ซ่อนอยู่')
                    ->falseLabel('ไม่ได้ซ่อน'),
            ])
            ->recordActions([
                Action::make('hide')
                    ->label('ซ่อน')
                    ->icon(Heroicon::OutlinedEyeSlash)
                    ->color('warning')
                    ->requiresConfirmation()
                    ->visible(fn (Product $record) => $record->hidden_at === null)
                    ->action(function (Product $record) {
                        $record->hidden_at = now();
                        $record->save();
                    }),

                // ตรวจแล้วไม่ผิดกฎ → แสดงอีกครั้ง และล้างรายงานเดิม
                Action::make('restore')
                    ->label('คืนสินค้า')
                    ->icon(Heroicon::OutlinedEye)
                    ->color('success')
                    ->requiresConfirmation()
                    ->modalDescription('สินค้าจะแสดงในตลาดอีกครั้ง และรายงานเดิมจะถูกล้าง')
                    ->visible(fn (Product $record) => $record->hidden_at !== null)
                    ->action(function (Product $record) {
                        $record->reports()->delete();
                        $record->hidden_at = null;
                        $record->save();
                    }),

                Action::make('dismissReports')
                    ->label('ล้างรายงาน')
                    ->icon(Heroicon::OutlinedCheckCircle)
                    ->color('gray')
                    ->requiresConfirmation()
                    ->visible(fn (Product $record) => $record->hidden_at === null && $record->reports_count > 0)
                    ->action(fn (Product $record) => $record->reports()->delete()),

                DeleteAction::make()
                    ->label('ลบ'),
            ]);
    }
}
