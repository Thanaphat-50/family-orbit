<?php

namespace App\Filament\Resources\AccountDeletionRequests\Pages;

use App\Filament\Resources\AccountDeletionRequests\AccountDeletionRequestResource;
use Filament\Resources\Pages\ListRecords;

class ListAccountDeletionRequests extends ListRecords
{
    protected static string $resource = AccountDeletionRequestResource::class;
}
