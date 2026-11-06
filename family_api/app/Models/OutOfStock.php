<?php

namespace App\Models;

use RuntimeException;

// สั่งซื้อมากกว่าจำนวนที่เหลือในสต็อก (Order::place)
class OutOfStock extends RuntimeException
{
    public function __construct(public readonly int $remaining, public readonly string $title = '')
    {
        parent::__construct("Only {$remaining} left in stock.");
    }
}
