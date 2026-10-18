<?php

namespace App\Http\Controllers;

use App\Models\Family;
use App\Models\FamilyMember;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use RuntimeException;
use Throwable;

class ProfileController extends Controller
{
    // GET /api/profile
    public function show(Request $request)
    {
        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        $family = $membership
            ? Family::find($membership->family_id)
            : null;

        return response()->json([
            'status' => true,
            'user' => $this->userPayload($request, $user),
            'family' => $family ? [
                'id' => $family->id,
                'name' => $family->name,
            ] : null,
            'role' => $membership ? $membership->role : null,
        ]);
    }

    // PUT /api/profile
    public function update(Request $request)
    {
        $user = $request->user();

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
        ]);

        $user->name = trim($validated['name']);
        $user->save();

        return response()->json([
            'status' => true,
            'message' => 'แก้ไขชื่อเรียบร้อยแล้ว',
            'user' => $this->userPayload($request, $user),
        ]);
    }

    // PUT /api/profile/password
    public function updatePassword(Request $request)
    {
        $user = $request->user();

        $validated = $request->validate([
            'current_password' => ['required', 'string'],
            'password' => [
                'required',
                'string',
                'min:8',
                'confirmed',
            ],
        ]);

        if (!Hash::check(
            $validated['current_password'],
            $user->password
        )) {
            return response()->json([
                'status' => false,
                'message' => 'รหัสผ่านปัจจุบันไม่ถูกต้อง',
            ], 422);
        }

        $user->password = Hash::make(
            $validated['password']
        );

        $user->save();

        return response()->json([
            'status' => true,
            'message' => 'เปลี่ยนรหัสผ่านเรียบร้อยแล้ว',
        ]);
    }

    // รองรับชื่อเมธอดเดิมใน routes/api.php
    public function changePassword(Request $request)
    {
        return $this->updatePassword($request);
    }

    // POST /api/profile/photo
    public function uploadPhoto(Request $request)
    {
        $user = $request->user();

        $validated = $request->validate([
            'photo' => [
                'required',
                'image',
                'mimes:jpg,jpeg,png,webp',
                'max:5120',
            ],
        ], [
            'photo.required' => 'กรุณาเลือกรูปภาพ',
            'photo.image' => 'ไฟล์ที่เลือกต้องเป็นรูปภาพ',
            'photo.mimes' =>
                'รองรับเฉพาะ JPG, JPEG, PNG และ WEBP',
            'photo.max' => 'รูปภาพต้องมีขนาดไม่เกิน 5 MB',
        ]);

        $disk = $this->photoDisk();
        $oldPath = $user->profile_photo;

        // อัปโหลดรูปใหม่ก่อนลบรูปเก่า
        try {
            $newPath = $validated['photo']->store(
                'profile_photos',
                $disk
            );

            if (!$newPath) {
                throw new RuntimeException(
                    'Could not store the uploaded photo.'
                );
            }
        } catch (Throwable $e) {
            Log::error('Profile photo upload failed', [
                'user_id' => $user->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'status' => false,
                'message' =>
                    'อัปโหลดรูปไม่สำเร็จ กรุณาลองอีกครั้ง',
            ], 500);
        }

        // บันทึกที่อยู่ของรูปลง MySQL
        try {
            $user->profile_photo = $newPath;
            $user->save();
        } catch (Throwable $e) {
            $this->removeFile($disk, $newPath);

            Log::error('Saving profile photo path failed', [
                'user_id' => $user->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'status' => false,
                'message' => 'บันทึกรูปโปรไฟล์ไม่สำเร็จ',
            ], 500);
        }

        // ลบรูปเก่าหลังจากบันทึกรูปใหม่สำเร็จ
        if ($oldPath && $oldPath !== $newPath) {
            $this->removeFile($disk, $oldPath);
        }

        return response()->json([
            'status' => true,
            'message' => 'เปลี่ยนรูปโปรไฟล์เรียบร้อยแล้ว',
            'user' => $this->userPayload($request, $user),
        ]);
    }

    // DELETE /api/profile/photo
    public function deletePhoto(Request $request)
    {
        $user = $request->user();
        $oldPath = $user->profile_photo;

        if (!$oldPath) {
            return response()->json([
                'status' => true,
                'message' => 'บัญชีนี้ไม่มีรูปโปรไฟล์',
            ]);
        }

        $user->profile_photo = null;
        $user->save();

        $this->removeFile(
            $this->photoDisk(),
            $oldPath
        );

        return response()->json([
            'status' => true,
            'message' => 'ลบรูปโปรไฟล์เรียบร้อยแล้ว',
            'user' => $this->userPayload($request, $user),
        ]);
    }

    // ในเครื่องใช้ public
    // บน Cloud ใช้ Default Disk ที่เชื่อมกับ Bucket
    private function photoDisk(): string
    {
        return User::profilePhotoDisk();
    }

    private function userPayload(
        Request $request,
        User $user
    ): array {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'profile_photo' => $user->profile_photo,
            'profile_photo_url' => $this->getPhotoUrl(
                $request,
                $user->profile_photo
            ),
        ];
    }

    private function getPhotoUrl(
        Request $request,
        ?string $path
    ): ?string {
        if (!$path) {
            return null;
        }

        $disk = $this->photoDisk();

        // URL สำหรับรันในเครื่อง
        if ($disk === 'public') {
            return $request->getSchemeAndHttpHost()
                . '/storage/'
                . ltrim($path, '/');
        }

        // URL ชั่วคราวสำหรับ Private Bucket
        try {
            return Storage::disk($disk)->temporaryUrl(
                $path,
                now()->addHours(12)
            );
        } catch (Throwable $e) {
            Log::warning(
                'Could not generate profile photo URL',
                ['error' => $e->getMessage()]
            );

            return null;
        }
    }

    private function removeFile(
        string $disk,
        string $path
    ): void {
        try {
            Storage::disk($disk)->delete($path);
        } catch (Throwable $e) {
            Log::warning(
                'Could not delete old profile photo',
                ['error' => $e->getMessage()]
            );
        }
    }
}
