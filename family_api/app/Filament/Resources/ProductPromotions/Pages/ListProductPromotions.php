<?php

namespace App\Filament\Resources\ProductPromotions\Pages;

use App\Filament\Resources\ProductPromotions\ProductPromotionResource;
use Filament\Resources\Pages\ListRecords;

class ListProductPromotions extends ListRecords
{
    protected static string $resource = ProductPromotionResource::class;
}
