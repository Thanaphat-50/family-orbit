<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\AccountDeletionRequestController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\FamilyController;
use App\Http\Controllers\FollowController;
use App\Http\Controllers\HistoryController;
use App\Http\Controllers\LocationController;
use App\Http\Controllers\MapStatusController;
use App\Http\Controllers\PostController;
use App\Http\Controllers\ChatController;
use App\Http\Controllers\CommentController;
use App\Http\Controllers\CommunityController;
use App\Http\Controllers\DeviceTokenController;
use App\Http\Controllers\MarketController;
use App\Http\Controllers\MyProductController;
use App\Http\Controllers\MyShopController;
use App\Http\Controllers\ActivityController;
use App\Http\Controllers\ProfileController;
use App\Http\Controllers\SettingsController;
use App\Http\Controllers\SocialAuthController;
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

// จำกัดจำนวนครั้ง (ตั้งค่าใน AppServiceProvider)
Route::post('/register', [AuthController::class, 'register'])
    ->middleware('throttle:register');

Route::post('/login', [AuthController::class, 'login'])
    ->middleware('throttle:login');

// เข้าสู่ระบบ / สมัคร ด้วย Google, LINE, Facebook
Route::get('/auth/providers', [SocialAuthController::class, 'providers']);

Route::post('/auth/social/{provider}', [SocialAuthController::class, 'login'])
    ->middleware('throttle:login');

Route::post('/logout', [AuthController::class, 'logout'])
    ->middleware('auth:sanctum');

// ลบบัญชี (จำกัด 5 ครั้ง/นาที กันเดารหัสผ่าน)
// แอปเวอร์ชันเก่า: "ลบบัญชี" → ส่งคำขอลบแทน
Route::delete('/account', [AccountDeletionRequestController::class, 'store'])
    ->middleware(['auth:sanctum', 'throttle:5,1']);

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

    // เส้นทางตามถนนไปหาสมาชิก (Google Routes API)
    Route::get('/family/members/{user}/route', [
        LocationController::class,
        'route'
    ])->middleware('throttle:route');

    Route::get('/posts', [
        PostController::class,
        'index'
    ]);

    // throttle:ugc = กันสแปมโพสต์/ความคิดเห็น/รายงาน (ตั้งค่าใน AppServiceProvider)
    Route::post('/posts', [
        PostController::class,
        'store'
    ])->middleware('throttle:ugc');

    Route::get('/posts/{post}', [
        PostController::class,
        'show'
    ]);

    Route::delete('/posts/{post}', [
        PostController::class,
        'destroy'
    ]);

    Route::post('/posts/{post}/comments', [
        CommentController::class,
        'store'
    ])->middleware('throttle:ugc');

    Route::post('/posts/{post}/report', [
        PostController::class,
        'report'
    ])->middleware('throttle:ugc');

    Route::post('/posts/{post}/like', [
        PostController::class,
        'like'
    ])->middleware('throttle:ugc');

    // แชร์: ส่งต่อไปแอปอื่น / แชร์ซ้ำในชุมชน / ส่งให้ครอบครัว
    Route::post('/posts/{post}/share', [
        PostController::class,
        'share'
    ])->middleware('throttle:ugc');

    // ติดตามผู้ใช้อื่น
    Route::get('/users/suggestions', [
        FollowController::class,
        'suggestions'
    ]);

    Route::post('/users/{user}/follow', [
        FollowController::class,
        'store'
    ])->middleware('throttle:ugc');

    Route::delete('/users/{user}/follow', [
        FollowController::class,
        'destroy'
    ]);

    // ประวัติการใช้งานของเรา
    Route::get('/me/history', [
        HistoryController::class,
        'index'
    ]);

    Route::delete('/me/history', [
        HistoryController::class,
        'clear'
    ]);

    // ข้อความบนแผนที่ (แสดง / เอาออก)
    Route::post('/posts/{post}/map-status', [
        MapStatusController::class,
        'store'
    ]);

    Route::delete('/posts/{post}/map-status', [
        MapStatusController::class,
        'destroy'
    ]);

    Route::post('/comments/{comment}/report', [
        CommentController::class,
        'report'
    ])->middleware('throttle:ugc');

    // ชุมชน: กฎชุมชน และการบล็อกผู้ใช้
    Route::post('/community/accept-terms', [
        CommunityController::class,
        'acceptTerms'
    ]);

    Route::get('/blocks', [
        CommunityController::class,
        'blocks'
    ]);

    Route::post('/users/{user}/block', [
        CommunityController::class,
        'block'
    ]);

    Route::delete('/users/{user}/block', [
        CommunityController::class,
        'unblock'
    ]);

    // แชทส่วนตัว (คนในครอบครัวเดียวกัน)
    Route::get('/chats', [
        ChatController::class,
        'index'
    ]);

    Route::get('/chats/unread-count', [
        ChatController::class,
        'unreadCount'
    ]);

    Route::post('/chats', [
        ChatController::class,
        'open'
    ]);

    Route::get('/chats/{conversation}/messages', [
        ChatController::class,
        'messages'
    ]);

    Route::post('/chats/{conversation}/messages', [
        ChatController::class,
        'send'
    ])->middleware('throttle:chat');

    Route::delete('/chats/{conversation}/messages/{message}', [
        ChatController::class,
        'destroy'
    ]);

    // บัญชี Google / LINE / Facebook ที่เชื่อมไว้ (หน้าตั้งค่า)
    Route::get('/social-accounts', [
        SocialAuthController::class,
        'index'
    ]);

    Route::post('/social-accounts/{provider}', [
        SocialAuthController::class,
        'link'
    ])->middleware('throttle:login');

    Route::delete('/social-accounts/{provider}', [
        SocialAuthController::class,
        'unlink'
    ]);

    // คำขอลบบัญชี (ผู้ดูแลเป็นคนลบ)
    Route::get('/account/deletion-request', [
        AccountDeletionRequestController::class,
        'show'
    ]);

    Route::post('/account/deletion-request', [
        AccountDeletionRequestController::class,
        'store'
    ])->middleware('throttle:5,1');

    Route::delete('/account/deletion-request', [
        AccountDeletionRequestController::class,
        'destroy'
    ]);

    // มือถือสำหรับแจ้งเตือนเด้ง (ออกจากระบบแล้วถูกลบเอง)
    Route::post('/device-tokens', [
        DeviceTokenController::class,
        'store'
    ]);

    Route::get('/users/{user}/profile', [
        CommunityController::class,
        'profile'
    ]);

    Route::post('/users/{user}/report', [
        CommunityController::class,
        'report'
    ])->middleware('throttle:ugc');

    Route::delete('/comments/{comment}', [
        CommentController::class,
        'destroy'
    ]);

    // ตลาด: ฝั่งผู้ซื้อ
    Route::get('/market/products', [
        MarketController::class,
        'products'
    ]);

    Route::get('/market/products/{product}', [
        MarketController::class,
        'showProduct'
    ]);

    Route::post('/market/products/{product}/report', [
        MarketController::class,
        'reportProduct'
    ])->middleware('throttle:ugc');

    // ร้านแนะนำ (ร้านที่เช่าพื้นที่) บนสุดของตลาด
    Route::get('/market/featured', [
        MarketController::class,
        'featured'
    ]);

    Route::get('/market/shops/{shop}', [
        MarketController::class,
        'showShop'
    ]);

    Route::post('/market/shops/{shop}/report', [
        MarketController::class,
        'reportShop'
    ])->middleware('throttle:ugc');

    // ตลาด: ร้านของฉัน (ฝั่งผู้ขาย)
    Route::get('/my-shop', [
        MyShopController::class,
        'show'
    ]);

    Route::post('/my-shop', [
        MyShopController::class,
        'store'
    ])->middleware('throttle:ugc');

    Route::post('/my-shop/update', [
        MyShopController::class,
        'update'
    ])->middleware('throttle:ugc');

    // ตลาด: สินค้าในร้านของฉัน
    Route::get('/my-shop/products', [
        MyProductController::class,
        'index'
    ]);

    Route::post('/my-shop/products', [
        MyProductController::class,
        'store'
    ])->middleware('throttle:ugc');

    Route::post('/my-shop/products/{product}/update', [
        MyProductController::class,
        'update'
    ])->middleware('throttle:ugc');

    Route::patch('/my-shop/products/{product}/status', [
        MyProductController::class,
        'updateStatus'
    ]);

    Route::delete('/my-shop/products/{product}', [
        MyProductController::class,
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

    // ตั้งค่า: แชร์ตำแหน่ง และการแจ้งเตือน
    Route::get('/settings', [
        SettingsController::class,
        'show'
    ]);

    Route::put('/settings', [
        SettingsController::class,
        'update'
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

    // ต้องอยู่ก่อน /notifications/{notification}
    // ไม่งั้นคำว่า "read" จะถูกมองเป็นเลข ID
    Route::delete('/notifications/read', [
        NotificationController::class,
        'clearRead'
    ]);

    Route::delete('/notifications/{notification}', [
        NotificationController::class,
        'destroy'
    ]);

    Route::patch(
    '/activities/{activity}/visibility',
    [
        ActivityController::class,
        'updateVisibility'
    ]);

});