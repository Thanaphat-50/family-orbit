<?php

namespace App\Filament\Resources\AccountDeletionRequests\Tables;

use App\Models\AccountDeletionRequest;
use App\Services\AccountDeletionService;
use Filament\Actions\Action;
use Filament\Forms\Components\Textarea;
use Filament\Notifications\Notification;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Auth;
use RuntimeException;

class AccountDeletionRequestsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('created_at', 'desc')
            ->columns([
                TextColumn::make('name')
                    ->label('ผู้ใช้')
                    ->description(fn (AccountDeletionRequest $record) => $record->email)
                    ->searchable(['name', 'email']),

                TextColumn::make('source')
                    ->label('ส่งจาก')
                    ->formatStateUsing(fn (string $state) => $state === 'web' ? 'หน้าเว็บ' : 'แอป')
                    ->badge()
                    ->color('gray'),

                TextColumn::make('reason')
                    ->label('เหตุผล')
                    ->placeholder('-')
                    ->limit(60)
                    ->wrap(),

                TextColumn::make('created_at')
                    ->label('ส่งเมื่อ')
                    ->since()
                    // ใกล้ครบกำหนด (เหลือไม่ถึง 7 วัน) → สีแดง
                    ->color(fn (AccountDeletionRequest $record) => $record->isPending()
                        && $record->created_at->lt(now()->subDays(AccountDeletionRequest::PROCESS_WITHIN_DAYS - 7))
                        ? 'danger'
                        : null)
                    ->sortable(),

                TextColumn::make('status')
                    ->label('สถานะ')
                    ->formatStateUsing(fn (string $state) => AccountDeletionRequest::STATUS_LABELS[$state] ?? $state)
                    ->description(fn (AccountDeletionRequest $record) => $record->note)
                    ->badge()
                    ->color(fn (string $state) => match ($state) {
                        AccountDeletionRequest::STATUS_PENDING => 'warning',
                        AccountDeletionRequest::STATUS_COMPLETED => 'success',
                        AccountDeletionRequest::STATUS_REJECTED => 'danger',
                        default => 'gray',
                    }),

                TextColumn::make('processor.name')
                    ->label('ดำเนินการโดย')
                    ->placeholder('-')
                    ->description(fn (AccountDeletionRequest $record) => $record->processed_at?->diffForHumans()),
            ])
            ->recordActions([
                Action::make('complete')
                    ->label('ลบบัญชี')
                    ->icon(Heroicon::OutlinedTrash)
                    ->color('danger')
                    ->requiresConfirmation()
                    ->modalHeading('ลบบัญชีนี้ถาวร?')
                    ->modalDescription('ข้อมูลทั้งหมดของผู้ใช้ (โพสต์ แชท ร้านค้า รูป ฯลฯ) จะถูกลบและกู้คืนไม่ได้')
                    ->modalSubmitActionLabel('ลบบัญชีถาวร')
                    ->visible(fn (AccountDeletionRequest $record) => $record->isPending())
                    ->action(function (AccountDeletionRequest $record) {
                        try {
                            app(AccountDeletionService::class)->completeRequest($record, Auth::user());
                        } catch (RuntimeException $e) {
                            Notification::make()
                                ->danger()
                                ->title('ลบไม่ได้')
                                ->body($e->getMessage())
                                ->send();

                            return;
                        }

                        Notification::make()
                            ->success()
                            ->title('ลบบัญชีแล้ว')
                            ->send();
                    }),

                Action::make('reject')
                    ->label('ไม่ลบ')
                    ->icon(Heroicon::OutlinedXCircle)
                    ->color('gray')
                    ->visible(fn (AccountDeletionRequest $record) => $record->isPending())
                    ->schema([
                        Textarea::make('note')
                            ->label('เหตุผล (ผู้ใช้จะเห็นข้อความนี้ในการแจ้งเตือน)')
                            ->required()
                            ->maxLength(500),
                    ])
                    ->action(function (AccountDeletionRequest $record, array $data) {
                        app(AccountDeletionService::class)->rejectRequest($record, Auth::user(), $data['note']);
                    }),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('สถานะ')
                    ->options(AccountDeletionRequest::STATUS_LABELS)
                    ->default(AccountDeletionRequest::STATUS_PENDING),
            ]);
    }
}
