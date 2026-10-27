<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Services\AccountDeletionService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function register(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|unique:users,email',
            'password' => 'required|string|min:8|confirmed',
        ]);

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
        ]);

        $token = $user->createToken('family-app')->plainTextToken;

        return response()->json([
            'status' => true,
            'message' => 'Register successful',
            'user' => $user,
            'token' => $token,
        ], 201);
    }

    public function login(Request $request)
    {
        $data = $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        $user = User::where('email', $data['email'])->first();

        if (!$user || !Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => ['Email or password is incorrect.'],
            ]);
        }

        $token = $user->createToken('family-app')->plainTextToken;

        return response()->json([
            'status' => true,
            'message' => 'Login successful',
            'user' => $user,
            'token' => $token,
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'status' => true,
            'message' => 'Logout successful',
        ]);
    }

    // =====================================================
    // DELETE /api/account
    // ลบบัญชีและข้อมูลทั้งหมด
    // - มีรหัสผ่าน: ยืนยันด้วยรหัสผ่าน
    // - สมัครด้วย Google / LINE / Facebook (ไม่มีรหัสผ่าน): พิมพ์คำว่า "ลบบัญชี"
    // =====================================================

    public const DELETE_CONFIRM_TEXT = 'ลบบัญชี';

    public function deleteAccount(
        Request $request,
        AccountDeletionService $deletion
    ) {
        $user = $request->user();

        if ($user->hasPassword()) {
            $data = $request->validate([
                'password' => 'required|string',
            ]);

            if (!Hash::check($data['password'], $user->password)) {
                return response()->json([
                    'status' => false,
                    'message' => 'รหัสผ่านไม่ถูกต้อง',
                ], 422);
            }
        } elseif (trim((string) $request->input('confirm_text')) !== self::DELETE_CONFIRM_TEXT) {
            return response()->json([
                'status' => false,
                'message' => 'กรุณาพิมพ์คำว่า "' . self::DELETE_CONFIRM_TEXT . '" เพื่อยืนยัน',
            ], 422);
        }

        $reason = $deletion->blockingReason($user);

        if ($reason !== null) {
            return response()->json([
                'status' => false,
                'code' => 'transfer_owner_required',
                'message' => $reason,
            ], 409);
        }

        $deletion->delete($user);

        return response()->json([
            'status' => true,
            'message' => 'ลบบัญชีและข้อมูลทั้งหมดเรียบร้อยแล้ว',
        ]);
    }
}