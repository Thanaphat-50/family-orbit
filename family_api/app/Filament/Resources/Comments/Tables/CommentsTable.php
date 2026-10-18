<?php

namespace App\Filament\Resources\Comments\Tables;

use App\Models\Comment;
use Filament\Actions\Action;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteAction;
use Filament\Actions\DeleteBulkAction;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class CommentsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                TextColumn::make('user.name')
                    ->label('ผู้แสดงความคิดเห็น')
                    ->description(fn (Comment $record) => $record->user?->email)
                    ->searchable(),

                TextColumn::make('content')
                    ->label('ความคิดเห็น')
                    ->limit(200)
                    ->wrap()
                    ->searchable(),

                TextColumn::make('post.content')
                    ->label('ในโพสต์')
                    ->limit(60)
                    ->wrap()
                    ->color('gray'),

                TextColumn::make('reports_count')
                    ->label('รายงาน')
                    ->badge()
                    ->color(fn (int $state) => $state > 0 ? 'danger' : 'gray')
                    ->sortable(),

                TextColumn::make('status')
                    ->label('สถานะ')
                    ->state(fn (Comment $record) => $record->hidden_at ? 'ซ่อนอยู่' : 'แสดงอยู่')
                    ->badge()
                    ->color(fn (string $state) => $state === 'ซ่อนอยู่' ? 'warning' : 'success'),

                TextColumn::make('created_at')
                    ->label('เมื่อ')
                    ->since()
                    ->sortable(),
            ])
            ->filters([
                Filter::make('reported')
                    ->label('ถูกรายงาน')
                    ->query(fn (Builder $query) => $query->has('reports')),

                TernaryFilter::make('hidden_at')
                    ->label('สถานะ')
                    ->nullable()
                    ->trueLabel('ซ่อนอยู่')
                    ->falseLabel('แสดงอยู่'),
            ])
            ->recordActions([
                Action::make('hide')
                    ->label('ซ่อน')
                    ->icon(Heroicon::OutlinedEyeSlash)
                    ->color('warning')
                    ->requiresConfirmation()
                    ->visible(fn (Comment $record) => $record->hidden_at === null)
                    ->action(function (Comment $record) {
                        $record->hidden_at = now();
                        $record->save();
                    }),

                // ตรวจแล้วไม่ผิดกฎ → แสดงอีกครั้ง และล้างรายงานเดิม
                Action::make('restore')
                    ->label('คืนความคิดเห็น')
                    ->icon(Heroicon::OutlinedEye)
                    ->color('success')
                    ->requiresConfirmation()
                    ->modalDescription('ความคิดเห็นจะแสดงอีกครั้ง และรายงานเดิมจะถูกล้าง')
                    ->visible(fn (Comment $record) => $record->hidden_at !== null)
                    ->action(function (Comment $record) {
                        $record->reports()->delete();
                        $record->hidden_at = null;
                        $record->save();
                    }),

                Action::make('dismissReports')
                    ->label('ล้างรายงาน')
                    ->icon(Heroicon::OutlinedCheckCircle)
                    ->color('gray')
                    ->requiresConfirmation()
                    ->visible(fn (Comment $record) => $record->hidden_at === null && $record->reports_count > 0)
                    ->action(fn (Comment $record) => $record->reports()->delete()),

                DeleteAction::make()
                    ->label('ลบ'),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make(),
                ]),
            ]);
    }
}
