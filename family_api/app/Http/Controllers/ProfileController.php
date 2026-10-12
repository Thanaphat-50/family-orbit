<?php

namespace App\Http\Controllers;

use App\Models\Family;
use App\Models\FamilyMember;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;

class ProfileController extends Controller
{
    // =====================================================
    // GET /api/profile
    // =====================================================

    public function show(Request $request)
    {
        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        $family = null;

        if ($membership) {
            $family = Family::find(
                $membership->family_id
            );
        }

        return response()->json([
            'status' => true,

            'user' => [
                'id' =>
                    $user->id,

                'name' =>
                    $user->name,

                'email' =>
                    $user->email,

                'profile_photo' =>
                    $user->profile_photo,

                'profile_photo_url' =>
                    $this->getPhotoUrl(
                        $request,
                        $user->profile_photo
                    ),
            ],

            'family' =>
                $family
                    ? [
                        'id' =>
                            $family->id,

                        'name' =>
                            $family->name,
                    ]
                    : null,

            'role' =>
                $membership
                    ? $membership->role
                    : null,
        ]);
    }

    // =====================================================
    // PUT /api/profile
    // แก้ชื่อ
    // =====================================================

    public function update(Request $request)
    {
        $user = $request->user();

        $validated =
            $request->validate([
                'name' => [
                    'required',
                    'string',
                    'max:255',
                ],
            ]);

        $user->name =
            trim(
                $validated['name']
            );

        $user->save();

        return response()->json([
            'status' => true,

            'message' =>
                'แก้ไขชื่อเรียบร้อยแล้ว',

            'user' => [
                'id' =>
                    $user->id,

                'name' =>
                    $user->name,

                'email' =>
                    $user->email,

                'profile_photo' =>
                    $user->profile_photo,

                'profile_photo_url' =>
                    $this->getPhotoUrl(
                        $request,
                        $user->profile_photo
                    ),
            ],
        ]);
    }

    // =====================================================
    // PUT /api/profile/password
    // =====================================================

    public function updatePassword(
        Request $request
    ) {
        $user = $request->user();

        $validated =
            $request->validate([
                'current_password' => [
                    'required',
                    'string',
                ],

                'password' => [
                    'required',
                    'string',
                    'min:8',
                    'confirmed',
                ],
            ]);

        if (
            !Hash::check(
                $validated[
                    'current_password'
                ],
                $user->password
            )
        ) {
            return response()->json([
                'status' => false,

                'message' =>
                    'รหัสผ่านปัจจุบันไม่ถูกต้อง',
            ], 422);
        }

        $user->password =
            Hash::make(
                $validated['password']
            );

        $user->save();

        return response()->json([
            'status' => true,

            'message' =>
                'เปลี่ยนรหัสผ่านเรียบร้อยแล้ว',
        ]);
    }

    // =====================================================
    // POST /api/profile/photo
    //
    // Upload / Replace รูป
    // =====================================================

    public function uploadPhoto(
        Request $request
    ) {
        $user = $request->user();

        $validated =
            $request->validate([
                'photo' => [
                    'required',
                    'image',
                    'mimes:jpg,jpeg,png,webp',
                    'max:5120',
                ],
            ], [
                'photo.required' =>
                    'กรุณาเลือกรูปภาพ',

                'photo.image' =>
                    'ไฟล์ที่เลือกต้องเป็นรูปภาพ',

                'photo.mimes' =>
                    'รองรับเฉพาะ JPG, JPEG, PNG และ WEBP',

                'photo.max' =>
                    'รูปภาพต้องมีขนาดไม่เกิน 5 MB',
            ]);

        // ---------------------------------------------
        // ลบรูปเก่า
        // ---------------------------------------------

        if (
            $user->profile_photo
            && Storage::disk('public')
                ->exists(
                    $user->profile_photo
                )
        ) {
            Storage::disk('public')
                ->delete(
                    $user->profile_photo
                );
        }

        // ---------------------------------------------
        // เก็บรูปใหม่
        // ---------------------------------------------

        $path =
            $request
                ->file('photo')
                ->store(
                    'profile_photos',
                    'public'
                );

        $user->profile_photo =
            $path;

        $user->save();

        return response()->json([
            'status' => true,

            'message' =>
                'เปลี่ยนรูปโปรไฟล์เรียบร้อยแล้ว',

            'user' => [
                'id' =>
                    $user->id,

                'name' =>
                    $user->name,

                'email' =>
                    $user->email,

                'profile_photo' =>
                    $user->profile_photo,

                'profile_photo_url' =>
                    $this->getPhotoUrl(
                        $request,
                        $user->profile_photo
                    ),
            ],
        ]);
    }

    // =====================================================
    // DELETE /api/profile/photo
    // =====================================================

    public function deletePhoto(
        Request $request
    ) {
        $user = $request->user();

        if (!$user->profile_photo) {
            return response()->json([
                'status' => true,

                'message' =>
                    'บัญชีนี้ไม่มีรูปโปรไฟล์',
            ]);
        }

        if (
            Storage::disk('public')
                ->exists(
                    $user->profile_photo
                )
        ) {
            Storage::disk('public')
                ->delete(
                    $user->profile_photo
                );
        }

        $user->profile_photo =
            null;

        $user->save();

        return response()->json([
            'status' => true,

            'message' =>
                'ลบรูปโปรไฟล์เรียบร้อยแล้ว',

            'user' => [
                'id' =>
                    $user->id,

                'name' =>
                    $user->name,

                'email' =>
                    $user->email,

                'profile_photo' =>
                    null,

                'profile_photo_url' =>
                    null,
            ],
        ]);
    }

    // =====================================================
    // PHOTO URL
    // =====================================================

    private function getPhotoUrl(
        Request $request,
        ?string $path
    ): ?string {
        if (!$path) {
            return null;
        }

        return
            $request->getSchemeAndHttpHost()
            . '/storage/'
            . ltrim(
                $path,
                '/'
            );
    }
}