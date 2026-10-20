<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    // จำนวนการแจ้งเตือนต่อหน้า
    private const PAGE_SIZE = 20;

    // =========================================
    // ดู Notification ของ User (ใหม่ล่าสุดก่อน)
    // GET /api/notifications              → ชุดแรก
    // GET /api/notifications?before_id=N  → ชุดถัดไป (เก่ากว่ารายการ N)
    //
    // ใช้ before_id แทนเลขหน้า เพราะถ้าลบรายการระหว่างเลื่อน
    // เลขหน้าจะเลื่อนตำแหน่งแล้วข้ามบางรายการไป
    // =========================================

    public function index(Request $request)
    {
        $data = $request->validate([
            'before_id' => 'nullable|integer|min:1',
        ]);

        $rows = AppNotification::where(
            'user_id',
            $request->user()->id
        )
            ->when(
                $data['before_id'] ?? null,
                fn ($query, $beforeId) => $query->where('id', '<', $beforeId)
            )
            ->orderByDesc('id')
            ->limit(self::PAGE_SIZE + 1)
            ->get();

        return response()->json([
            'status' => true,
            'notifications' => $rows->take(self::PAGE_SIZE)->values(),
            'has_more' => $rows->count() > self::PAGE_SIZE,
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
        if (!$this->owns($request, $notification)) {
            return $this->forbidden();
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

    // =========================================
    // ลบ Notification 1 รายการ
    // DELETE /api/notifications/{notification}
    // =========================================

    public function destroy(
        Request $request,
        AppNotification $notification
    ) {
        if (!$this->owns($request, $notification)) {
            return $this->forbidden();
        }

        $notification->delete();

        return response()->json([
            'status' => true,
            'message' => 'ลบการแจ้งเตือนแล้ว',
        ]);
    }

    // =========================================
    // ลบทุกรายการที่อ่านแล้ว
    // DELETE /api/notifications/read
    // =========================================

    public function clearRead(
        Request $request
    ) {
        $deleted = AppNotification::where(
            'user_id',
            $request->user()->id
        )
            ->where('is_read', true)
            ->delete();

        return response()->json([
            'status' => true,
            'deleted' => $deleted,
            'message' => $deleted > 0
                ? "ลบการแจ้งเตือนที่อ่านแล้ว {$deleted} รายการ"
                : 'ไม่มีการแจ้งเตือนที่อ่านแล้ว',
        ]);
    }

    // =========================================
    // HELPERS
    // =========================================

    private function owns(
        Request $request,
        AppNotification $notification
    ): bool {
        return (int) $notification->user_id === (int) $request->user()->id;
    }

    private function forbidden()
    {
        return response()->json([
            'status' => false,
            'message' =>
                'คุณไม่มีสิทธิ์เข้าถึงการแจ้งเตือนนี้',
        ], 403);
    }
}
