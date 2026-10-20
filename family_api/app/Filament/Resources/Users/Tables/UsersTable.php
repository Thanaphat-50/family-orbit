<?php

namespace App\Filament\Resources\Users\Tables;

use App\Models\User;
use Filament\Actions\Action;
use Filament\Actions\ViewAction;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class UsersTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                TextColumn::make('name')
                    ->label('ชื่อ')
                    ->searchable(),

                TextColumn::make('email')
                    ->label('อีเมล')
                    ->searchable(),

                IconColumn::make('is_admin')
                    ->label('Admin')
                    ->boolean(),

                TextColumn::make('reports_received_count')
                    ->label('ถูกรายงาน')
                    ->badge()
                    ->color(fn (int $state) => $state > 0 ? 'danger' : 'gray')
                    ->sortable(),

                TextColumn::make('created_at')
                    ->label('สมัครเมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->filters([
                TernaryFilter::make('is_admin')
                    ->label('Admin'),

                Filter::make('reported')
                    ->label('ถูกรายงาน')
                    ->query(fn (Builder $query) => $query->has('reportsReceived')),
            ])
            ->recordActions([
                ViewAction::make()
                    ->label('ดู'),

                // ตรวจแล้วผู้ใช้ไม่ผิดกฎ → ล้างรายงาน
                Action::make('dismissReports')
                    ->label('ล้างรายงาน')
                    ->icon(Heroicon::OutlinedCheckBadge)
                    ->color('gray')
                    ->requiresConfirmation()
                    ->visible(fn (User $record) => $record->reports_received_count > 0)
                    ->action(fn (User $record) => $record->reportsReceived()->delete()),
            ]);
    }
}
