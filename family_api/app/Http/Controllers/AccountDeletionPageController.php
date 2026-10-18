<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Services\AccountDeletionService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

// =======================================================
// หน้าเว็บขอลบบัญชี (/account/delete)
// Google Play กำหนดให้ลบบัญชีได้โดยไม่ต้องเปิดแอป
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
        ], [
            'email.required' => 'กรุณากรอกอีเมล',
            'email.email' => 'รูปแบบอีเมลไม่ถูกต้อง',
            'password.required' => 'กรุณากรอกรหัสผ่าน',
            'confirm.accepted' => 'กรุณาติ๊กยืนยันว่าต้องการลบบัญชีถาวร',
        ]);

        $user = User::where('email', $data['email'])->first();

        if (!$user || !Hash::check($data['password'], $user->password)) {
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

        $deletion->delete($user);

        return view('account.deleted');
    }
}
