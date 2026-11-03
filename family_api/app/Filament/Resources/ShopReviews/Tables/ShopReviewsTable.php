<?php

namespace App\Filament\Resources\ShopReviews\Tables;

use App\Models\ShopReview;
use Filament\Actions\Action;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class ShopReviewsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                TextColumn::make('shop.name')
                    ->label('ร้าน')
                    ->searchable(),
                TextColumn::make('user.name')
                    ->label('ผู้รีวิว')
                    ->description(fn (ShopReview $record) => $record->user?->email)
                    ->searchable(),
                TextColumn::make('rating')
                    ->label('ดาว')
                    ->formatStateUsing(fn (int $state) => str_repeat('★', $state) . str_repeat('☆', 5 - $state))
                    ->color('warning')
                    ->sortable(),
                TextColumn::make('comment')
                    ->label('ข้อความ')
                    ->placeholder('-')
                    ->wrap()
                    ->limit(200)
                    ->searchable(),
                TextColumn::make('hidden_at')
                    ->label('สถานะ')
                    ->formatStateUsing(fn ($state) => $state ? 'ซ่อนอยู่' : 'แสดง')
                    ->default('แสดง')
                    ->badge()
                    ->color(fn (ShopReview $record) => $record->hidden_at ? 'danger' : 'success'),
                TextColumn::make('created_at')
                    ->label('เมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->recordActions([
                Action::make('hide')
                    ->label('ซ่อน')
                    ->icon(Heroicon::OutlinedEyeSlash)
                    ->color('danger')
                    ->requiresConfirmation()
                    ->visible(fn (ShopReview $record) => $record->hidden_at === null)
                    ->action(fn (ShopReview $record) => $record->forceFill(['hidden_at' => now()])->save()),
                Action::make('unhide')
                    ->label('แสดงอีกครั้ง')
                    ->icon(Heroicon::OutlinedEye)
                    ->color('gray')
                    ->visible(fn (ShopReview $record) => $record->hidden_at !== null)
                    ->action(fn (ShopReview $record) => $record->forceFill(['hidden_at' => null])->save()),
            ])
            ->filters([
                SelectFilter::make('rating')
                    ->label('ดาว')
                    ->options([1 => '1 ดาว', 2 => '2 ดาว', 3 => '3 ดาว', 4 => '4 ดาว', 5 => '5 ดาว']),
                Filter::make('hidden')
                    ->label('ซ่อนอยู่')
                    ->query(fn (Builder $query) => $query->whereNotNull('hidden_at')),
            ]);
    }
}
