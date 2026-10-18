<?php

use App\Http\Controllers\AccountDeletionPageController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// หน้าเว็บขอลบบัญชี (ลิงก์สำหรับ Google Play)
Route::get('/account/delete', [AccountDeletionPageController::class, 'show'])
    ->name('account.delete');

// จำกัด 5 ครั้ง/นาที กันเดารหัสผ่าน
Route::post('/account/delete', [AccountDeletionPageController::class, 'destroy'])
    ->middleware('throttle:5,1')
    ->name('account.delete.submit');
