<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\User;
use App\Models\UserLocation;
use Illuminate\Http\Request;

// =======================================================
// ตั้งค่าของผู้ใช้
// - แชร์ตำแหน่งกับครอบครัว (เปิด/ปิด)
// - เปิด/ปิดการแจ้งเตือนแต่ละประเภท
// =======================================================

class SettingsController extends Controller
{
    // GET /api/settings
    public function show(Request $request)
    {
        return response()->json([
            'status' => true,
            'settings' => $this->payload($request->user()),
        ]);
    }

    // PUT /api/settings (ส่งเฉพาะค่าที่เปลี่ยน)
    public function update(Request $request)
    {
        $data = $request->validate([
            'location_sharing' => 'sometimes|boolean',
            'notifications' => 'sometimes|array:' . implode(',', AppNotification::OPTIONAL_TYPES),
            'notifications.*' => 'boolean',
        ]);

        $user = $request->user();

        if (array_key_exists('notifications', $data)) {
            $user->notification_settings = [
                ...($user->notification_settings ?? []),
                ...array_map('boolval', $data['notifications']),
            ];
        }

        if (array_key_exists('location_sharing', $data)) {
            $user->location_sharing = (bool) $data['location_sharing'];
        }

        $user->save();

        // ปิดการแชร์ → ลบตำแหน่งล่าสุด ครอบครัวจะไม่เห็นตำแหน่งเก่าค้างอยู่
        if ($user->location_sharing === false) {
            UserLocation::where('user_id', $user->id)->delete();
        }

        return response()->json([
            'status' => true,
            'message' => 'บันทึกการตั้งค่าแล้ว',
            'settings' => $this->payload($user),
        ]);
    }

    private function payload(User $user): array
    {
        $notifications = [];

        foreach (AppNotification::OPTIONAL_TYPES as $type) {
            $notifications[$type] = $user->wantsNotification($type);
        }

        return [
            'location_sharing' => $user->location_sharing !== false,
            'notifications' => $notifications,
        ];
    }
}
