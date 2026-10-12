<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    // =========================================
    // ดู Notification ทั้งหมดของ User
    // =========================================

    public function index(Request $request)
    {
        $notifications =
            AppNotification::where(
                'user_id',
                $request->user()->id
            )
            ->latest()
            ->limit(50)
            ->get();

        return response()->json([
            'status' => true,
            'notifications' => $notifications,
        ]);
    }

    // =========================================
    // จำนวน Notification ที่ยังไม่ได้อ่าน
    // =========================================

    public function unreadCount(
        Request $request
    ) {
        $count =
            AppNotification::where(
                'user_id',
                $request->user()->id
            )
            ->where(
                'is_read',
                false
            )
            ->count();

        return response()->json([
            'status' => true,
            'count' => $count,
        ]);
    }

    // =========================================
    // อ่าน Notification 1 รายการ
    // =========================================

    public function markAsRead(
        Request $request,
        AppNotification $notification
    ) {
        if (
            $notification->user_id !==
            $request->user()->id
        ) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณไม่มีสิทธิ์เข้าถึงการแจ้งเตือนนี้',
            ], 403);
        }

        $notification->is_read = true;
        $notification->save();

        return response()->json([
            'status' => true,
            'message' =>
                'อ่านการแจ้งเตือนแล้ว',
        ]);
    }

    // =========================================
    // อ่านทั้งหมด
    // =========================================

    public function markAllAsRead(
        Request $request
    ) {
        AppNotification::where(
            'user_id',
            $request->user()->id
        )
        ->where(
            'is_read',
            false
        )
        ->update([
            'is_read' => true,
        ]);

        return response()->json([
            'status' => true,
            'message' =>
                'อ่านการแจ้งเตือนทั้งหมดแล้ว',
        ]);
    }
}