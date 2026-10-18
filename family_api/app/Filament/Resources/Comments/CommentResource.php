<?php

namespace App\Filament\Resources\Comments;

use App\Filament\Resources\Comments\Pages\ListComments;
use App\Filament\Resources\Comments\Tables\CommentsTable;
use App\Models\Comment;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

// =======================================================
// ความคิดเห็นในโพสต์ชุมชน: ตรวจรายงาน ซ่อน / คืน / ลบ
// (ความคิดเห็นในโพสต์ครอบครัวเป็นข้อมูลส่วนตัว ไม่แสดงที่นี่)
// =======================================================

class CommentResource extends Resource
{
    protected static ?string $model = Comment::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedChatBubbleBottomCenterText;

    protected static ?string $modelLabel = 'ความคิดเห็นชุมชน';

    protected static ?string $pluralModelLabel = 'ความคิดเห็นชุมชน';

    protected static ?string $navigationLabel = 'ความคิดเห็นชุมชน';

    protected static ?int $navigationSort = 2;

    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()
            ->whereHas('post', fn (Builder $post) => $post->where('visibility', 'community'))
            ->with(['user:id,name,email', 'post:id,content'])
            ->withCount('reports');
    }

    // ตัวเลขบนเมนู = ความคิดเห็นที่ถูกรายงานแต่ยังไม่ถูกซ่อน (รอตรวจ)
    public static function getNavigationBadge(): ?string
    {
        $count = Comment::query()
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
        return CommentsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListComments::route('/'),
        ];
    }
}
