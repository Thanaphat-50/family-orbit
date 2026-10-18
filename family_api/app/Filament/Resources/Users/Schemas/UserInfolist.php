<?php

namespace App\Filament\Resources\Users\Schemas;

use Filament\Infolists\Components\IconEntry;
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
            ]);
    }
}
