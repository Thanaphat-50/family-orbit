<?php

namespace App\Http\Controllers;

use App\Models\AccountDeletionRequest;
use App\Services\AccountDeletionService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

// =======================================================
// คำขอลบบัญชีจากแอป
// ผู้ใช้ส่งคำขอ → ผู้ดูแลตรวจแล้วกดลบในหน้า Admin (ภายใน 30 วัน)
// ระหว่างรอ ผู้ใช้ยังใช้แอปได้ และยกเลิกคำขอได้
// =======================================================

class AccountDeletionRequestController extends Controller
{
    // บัญชีที่ไม่มีรหัสผ่าน (สมัครด้วย Google / LINE / Facebook) ยืนยันด้วยการพิมพ์คำนี้
    public const CONFIRM_TEXT = 'ลบบัญชี';

    // GET /api/account/deletion-request
    public function show(Request $request)
    {
        $pending = $request->user()
            ->deletionRequests()
            ->pending()
            ->latest('id')
            ->first();

        return response()->json([
            'status' => true,
            'request' => $pending?->payload(),
            'process_within_days' => AccountDeletionRequest::PROCESS_WITHIN_DAYS,
        ]);
    }

    // POST /api/account/deletion-request
    // (DELETE /api/account ของแอปเวอร์ชันเก่าก็มาที่นี่)
    public function store(Request $request, AccountDeletionService $deletion)
    {
        $user = $request->user();

        $data = $request->validate([
            'reason' => 'nullable|string|max:1000',
        ]);

        if ($user->hasPassword()) {
            $password = (string) $request->input('password');

            if ($password === '' || !Hash::check($password, $user->password)) {
                return response()->json([
                    'status' => false,
                    'message' => 'รหัสผ่านไม่ถูกต้อง',
                ], 422);
            }
        } elseif (trim((string) $request->input('confirm_text')) !== self::CONFIRM_TEXT) {
            return response()->json([
                'status' => false,
                'message' => 'กรุณาพิมพ์คำว่า "' . self::CONFIRM_TEXT . '" เพื่อยืนยัน',
            ], 422);
        }

        // Owner ที่ยังมีสมาชิก → โอนสิทธิ์ก่อน (ไม่อย่างนั้นผู้ดูแลก็ลบให้ไม่ได้)
        $reason = $deletion->blockingReason($user);

        if ($reason !== null) {
            return response()->json([
                'status' => false,
                'code' => 'transfer_owner_required',
                'message' => $reason,
            ], 409);
        }

        $deletionRequest = AccountDeletionRequest::requestFor($user, 'app', $data['reason'] ?? null);

        return response()->json([
            'status' => true,
            'message' => 'ส่งคำขอลบบัญชีแล้ว ทีมงานจะลบบัญชีและข้อมูลทั้งหมดให้ภายใน '
                . AccountDeletionRequest::PROCESS_WITHIN_DAYS . ' วัน',
            'request' => $deletionRequest->payload(),
        ]);
    }

    // DELETE /api/account/deletion-request → ยกเลิกคำขอ
    public function destroy(Request $request)
    {
        $canceled = $request->user()
            ->deletionRequests()
            ->pending()
            ->update([
                'status' => AccountDeletionRequest::STATUS_CANCELED,
                'processed_at' => now(),
            ]);

        return response()->json([
            'status' => true,
            'message' => $canceled > 0 ? 'ยกเลิกคำขอลบบัญชีแล้ว' : 'ไม่มีคำขอลบบัญชีที่รออยู่',
            'request' => null,
        ]);
    }
}
