<?php

namespace App\Filament\Resources\Posts;

use App\Filament\Resources\Posts\Pages\ListPosts;
use App\Filament\Resources\Posts\Tables\PostsTable;
use App\Models\Post;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// โพสต์ชุมชน: ตรวจรายงาน ซ่อน / คืน / ลบ
// (โพสต์ครอบครัวเป็นข้อมูลส่วนตัว ไม่แสดงในหน้า Admin)
// =======================================================

class PostResource extends Resource
{
    protected static ?string $model = Post::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedChatBubbleLeftRight;

    protected static ?string $modelLabel = 'โพสต์ชุมชน';

    protected static ?string $pluralModelLabel = 'โพสต์ชุมชน';

    protected static ?string $navigationLabel = 'โพสต์ชุมชน';

    protected static ?int $navigationSort = 1;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()
            ->where('visibility', 'community')
            ->with('user:id,name,email')
            ->withCount('reports');
    }

    // ตัวเลขบนเมนู = โพสต์ที่ถูกรายงานแต่ยังไม่ถูกซ่อน (รอตรวจ)
    public static function getNavigationBadge(): ?string
    {
        $count = Post::where('visibility', 'community')
            ->whereNull('hidden_at')
            ->has('reports')
            ->count();

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

    public static function table(Table $table): Table
    {
        return PostsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListPosts::route('/'),
        ];
    }
}
