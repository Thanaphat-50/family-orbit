<?php

namespace App\Filament\Resources\AccountDeletionRequests;

use App\Filament\Resources\AccountDeletionRequests\Pages\ListAccountDeletionRequests;
use App\Filament\Resources\AccountDeletionRequests\Tables\AccountDeletionRequestsTable;
use App\Models\AccountDeletionRequest;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

// =======================================================
// คำขอลบบัญชี: ผู้ดูแลกดลบบัญชี / ไม่ลบพร้อมเหตุผล
// ต้องดำเนินการภายใน 30 วัน (ตามที่แจ้งผู้ใช้และในนโยบาย)
// =======================================================

class AccountDeletionRequestResource extends Resource
{
    protected static ?string $model = AccountDeletionRequest::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedUserMinus;

    protected static ?string $modelLabel = 'คำขอลบบัญชี';

    protected static ?string $pluralModelLabel = 'คำขอลบบัญชี';

    protected static ?string $navigationLabel = 'คำขอลบบัญชี';

    protected static ?int $navigationSort = 4;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()->with('processor:id,name');
    }

    // ตัวเลขบนเมนู = คำขอที่รอดำเนินการ
    public static function getNavigationBadge(): ?string
    {
        $count = AccountDeletionRequest::pending()->count();

        return $count > 0 ? (string) $count : null;
    }

    public static function getNavigationBadgeColor(): ?string
    {
        return 'danger';
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function canEdit(Model $record): bool
    {
        return false;
    }

    public static function canDelete(Model $record): bool
    {
        return false;
    }

    public static function table(Table $table): Table
    {
        return AccountDeletionRequestsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListAccountDeletionRequests::route('/'),
        ];
    }
}
