<?php

namespace App\Http\Controllers;

use App\Models\DeviceToken;
use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;

// =======================================================
// มือถือสำหรับแจ้งเตือนเด้ง
// แอปส่งรหัสเครื่องมาทุกครั้งที่เข้าหน้าหลัก
// ออกจากระบบ → Token ของแอปถูกลบ → แถวของเครื่องนี้ถูกลบตาม (cascade)
// =======================================================

class DeviceTokenController extends Controller
{
    // POST /api/device-tokens
    public function store(Request $request)
    {
        $data = $request->validate([
            'token' => 'required|string|max:512',
            'platform' => 'nullable|in:android,ios',
        ]);

        $user = $request->user();

        $accessToken = $user->currentAccessToken();

        // เครื่องเดิมเปลี่ยนบัญชี → รหัสเครื่องย้ายมาเป็นของบัญชีนี้
        DeviceToken::updateOrCreate(
            ['token' => $data['token']],
            [
                'user_id' => $user->id,
                'access_token_id' => $accessToken instanceof PersonalAccessToken && $accessToken->exists
                    ? $accessToken->getKey()
                    : null,
                'platform' => $data['platform'] ?? 'android',
                'last_used_at' => now(),
            ]
        );

        // เก็บเฉพาะเครื่องล่าสุด
        $staleIds = DeviceToken::where('user_id', $user->id)
            ->orderByDesc('last_used_at')
            ->orderByDesc('id')
            ->skip(DeviceToken::MAX_PER_USER)
            ->take(PHP_INT_MAX)
            ->pluck('id');

        if ($staleIds->isNotEmpty()) {
            DeviceToken::whereIn('id', $staleIds)->delete();
        }

        return response()->json([
            'status' => true,
        ]);
    }
}
