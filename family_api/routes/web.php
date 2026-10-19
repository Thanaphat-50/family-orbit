<?php

use App\Http\Controllers\AccountDeletionPageController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// หน้านโยบาย (ลิงก์สำหรับ Google Play และในแอป)
Route::view('/privacy', 'legal.privacy', ['app' => config('legal.app_name')])
    ->name('legal.privacy');

Route::view('/terms', 'legal.terms', ['app' => config('legal.app_name')])
    ->name('legal.terms');

Route::view('/child-safety', 'legal.child-safety', ['app' => config('legal.app_name')])
    ->name('legal.child-safety');

// หน้าเว็บขอลบบัญชี (ลิงก์สำหรับ Google Play)
Route::get('/account/delete', [AccountDeletionPageController::class, 'show'])
    ->name('account.delete');

// จำกัด 5 ครั้ง/นาที กันเดารหัสผ่าน
Route::post('/account/delete', [AccountDeletionPageController::class, 'destroy'])
    ->middleware('throttle:5,1')
    ->name('account.delete.submit');
