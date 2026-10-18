<?php

namespace App\Filament\Resources\Users\Tables;

use Filament\Actions\ViewAction;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Table;

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

                TextColumn::make('created_at')
                    ->label('สมัครเมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->filters([
                TernaryFilter::make('is_admin')
                    ->label('Admin'),
            ])
            ->recordActions([
                ViewAction::make()
                    ->label('ดู'),
            ]);
    }
}
