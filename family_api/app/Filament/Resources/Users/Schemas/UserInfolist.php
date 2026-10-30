<?php

namespace App\Filament\Resources\Users\Schemas;

use App\Models\SocialAccount;
use App\Models\UserReport;
use Filament\Infolists\Components\IconEntry;
use Filament\Infolists\Components\RepeatableEntry;
use Filament\Infolists\Components\TextEntry;
use Filament\Schemas\Schema;

class UserInfolist
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextEntry::make('name')
                    ->label('ชื่อ'),

                TextEntry::make('email')
                    ->label('อีเมล'),

                IconEntry::make('is_admin')
                    ->label('Admin')
                    ->boolean(),

                TextEntry::make('community_terms_accepted_at')
                    ->label('ยอมรับกฎชุมชนเมื่อ')
                    ->dateTime()
                    ->placeholder('ยังไม่ยอมรับ'),

                TextEntry::make('created_at')
                    ->label('สมัครเมื่อ')
                    ->dateTime(),

                // ข้อมูลแนะนำตัวที่คนในชุมชนเห็น (ตรวจเมื่อมีคนรายงาน)
                TextEntry::make('bio')
                    ->label('แนะนำตัว')
                    ->placeholder('-')
                    ->columnSpanFull(),

                TextEntry::make('occupation')
                    ->label('งาน/อาชีพ')
                    ->placeholder('-'),

                TextEntry::make('education')
                    ->label('การศึกษา')
                    ->placeholder('-'),

                TextEntry::make('province')
                    ->label('จังหวัด')
                    ->placeholder('-'),

                TextEntry::make('interests')
                    ->label('ความสนใจ')
                    ->placeholder('-'),

                TextEntry::make('socialAccounts.provider')
                    ->label('เข้าสู่ระบบด้วย')
                    ->badge()
                    ->formatStateUsing(fn (string $state) => SocialAccount::LABELS[$state] ?? $state)
                    ->placeholder('อีเมลและรหัสผ่าน'),

                // รายงานจากผู้ใช้คนอื่น (ล่าสุดก่อน)
                RepeatableEntry::make('reportsReceived')
                    ->label('ถูกรายงาน')
                    ->placeholder('ยังไม่มีรายงาน')
                    ->columnSpanFull()
                    ->columns(3)
                    ->schema([
                        TextEntry::make('reason')
                            ->label('เหตุผล')
                            ->formatStateUsing(fn (string $state) => UserReport::REASONS[$state] ?? $state),

                        TextEntry::make('user.name')
                            ->label('ผู้รายงาน'),

                        TextEntry::make('created_at')
                            ->label('เมื่อ')
                            ->since(),

                        TextEntry::make('details')
                            ->label('รายละเอียด')
                            ->placeholder('-')
                            ->columnSpanFull(),
                    ]),
            ]);
    }
}
