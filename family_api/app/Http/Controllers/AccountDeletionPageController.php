<?php

namespace App\Http\Controllers;

use App\Models\AccountDeletionRequest;
use App\Models\User;
use App\Services\AccountDeletionService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

// =======================================================
// หน้าเว็บขอลบบัญชี (/account/delete)
// Google Play กำหนดให้ขอลบบัญชีได้โดยไม่ต้องเปิดแอป
// ยืนยันตัวตนแล้วส่งคำขอ → ผู้ดูแลลบให้ในหน้า Admin
// =======================================================

class AccountDeletionPageController extends Controller
{
    public function show()
    {
        return view('account.delete');
    }

    public function destroy(
        Request $request,
        AccountDeletionService $deletion
    ) {
        $data = $request->validate([
            'email' => 'required|email',
            'password' => 'required|string',
            'confirm' => 'accepted',
            'reason' => 'nullable|string|max:1000',
        ], [
            'email.required' => 'กรุณากรอกอีเมล',
            'email.email' => 'รูปแบบอีเมลไม่ถูกต้อง',
            'password.required' => 'กรุณากรอกรหัสผ่าน',
            'confirm.accepted' => 'กรุณาติ๊กยืนยันว่าต้องการลบบัญชีถาวร',
            'reason.max' => 'เหตุผลยาวเกินไป',
        ]);

        $user = User::where('email', $data['email'])->first();

        if (!$user || !$user->hasPassword() || !Hash::check($data['password'], $user->password)) {
            return back()
                ->withInput($request->only('email'))
                ->withErrors(['email' => 'อีเมลหรือรหัสผ่านไม่ถูกต้อง']);
        }

        $reason = $deletion->blockingReason($user);

        if ($reason !== null) {
            return back()
                ->withInput($request->only('email'))
                ->withErrors(['email' => $reason]);
        }

        AccountDeletionRequest::requestFor($user, 'web', $data['reason'] ?? null);

        return view('account.requested', [
            'days' => AccountDeletionRequest::PROCESS_WITHIN_DAYS,
        ]);
    }
}
