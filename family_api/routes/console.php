<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// ลบ Token ที่หมดอายุแล้วเกิน 24 ชั่วโมงออกจากฐานข้อมูลทุกวัน
// (ทำงานเมื่อเปิด Scheduler บน Laravel Cloud)
Schedule::command('sanctum:prune-expired --hours=24')->daily();
