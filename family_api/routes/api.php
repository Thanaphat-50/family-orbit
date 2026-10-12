<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\FamilyController;
use App\Http\Controllers\LocationController;
use App\Http\Controllers\PostController;
use App\Http\Controllers\CommentController;
use App\Http\Controllers\ActivityController;
use App\Http\Controllers\ProfileController;
use App\Http\Controllers\NotificationController;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

Route::get('/test', function () {
    return response()->json([
        'status' => true,
        'message' => 'Family API is working'
    ]);
});

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);

Route::post('/logout', [AuthController::class, 'logout'])
    ->middleware('auth:sanctum');

Route::middleware('auth:sanctum')->group(function () {

    Route::post('/families', [
        FamilyController::class,
        'create'
    ]);

    Route::post('/families/join', [
        FamilyController::class,
        'join'
    ]);

    Route::get('/families/current', [
        FamilyController::class,
        'current'
    ]);

    Route::post('/location', [
        LocationController::class,
        'update'
    ]);

    Route::get('/family/locations', [
        LocationController::class,
        'familyLocations'
    ]);

    Route::get('/posts', [
        PostController::class,
        'index'
    ]);

    Route::post('/posts', [
        PostController::class,
        'store'
    ]);

    Route::delete('/posts/{post}', [
        PostController::class,
        'destroy'
    ]);

    Route::post('/posts/{post}/comments', [
        CommentController::class,
        'store'
    ]);

    Route::delete('/comments/{comment}', [
        CommentController::class,
        'destroy'
    ]);

    Route::get('/activities', [
        ActivityController::class,
        'index'
    ]);

    Route::post('/activities', [
        ActivityController::class,
        'store'
    ]);

    Route::patch('/activities/{activity}/toggle', [
        ActivityController::class,
        'toggle'
    ]);

    Route::delete('/activities/{activity}', [
        ActivityController::class,
        'destroy'
    ]);

    Route::get('/profile', [
        ProfileController::class,
        'show'
    ]);

    Route::put('/profile', [
        ProfileController::class,
        'update'
    ]);

    Route::put('/profile/password', [
        ProfileController::class,
        'changePassword'
    ]);

    Route::post('/profile/photo',[
        ProfileController::class,
        'uploadPhoto'
    ]);

    Route::delete('/profile/photo',[
        ProfileController::class,
        'deletePhoto'
    ]);

    Route::put('/families/{family}', [
        FamilyController::class,
        'update'
    ]);

    Route::post('/families/regenerate-code', [
        FamilyController::class,
        'regenerateCode'
    ]);

    Route::delete('/families/members/{userId}', [
        FamilyController::class,
        'removeMember'
    ]);

    Route::post('/families/leave', [
        FamilyController::class,
        'leave'
    ]);

    Route::post('/families/transfer-owner/{userId}', [
            FamilyController::class,
            'transferOwner'
        ]
    );

    Route::delete('/families/current', [
        FamilyController::class,
        'deleteFamily'
    ]);

    Route::get('/notifications', [
        NotificationController::class,
        'index'
    ]);

    Route::get('/notifications/unread-count', [
        NotificationController::class,
        'unreadCount'
    ]);

    Route::patch('/notifications/read-all', [
        NotificationController::class,
        'markAllAsRead'
    ]);

    Route::patch('/notifications/{notification}/read', [
        NotificationController::class,
        'markAsRead'
    ]);

    Route::patch(
    '/activities/{activity}/visibility',
    [
        ActivityController::class,
        'updateVisibility'
    ]);

});