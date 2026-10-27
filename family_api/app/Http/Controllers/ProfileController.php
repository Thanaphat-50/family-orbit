<?php

namespace App\Http\Controllers;

use App\Models\Family;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\PostLike;
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
            'stats' => $this->stats($user, $membership),
        ]);
    }

    // ตัวเลขบนหน้าโปรไฟล์
    // posts:          โพสต์ของเรา (ชุมชน + ครอบครัวปัจจุบัน) ตรงกับหน้า "โพสต์ของฉัน"
    // likes_received: ถูกใจที่ได้รับในโพสต์เหล่านั้น
    private function stats(User $user, ?FamilyMember $membership): array
    {
        $myPosts = fn () => Post::where('user_id', $user->id)
            ->where(function ($query) use ($membership) {
                $query->where('visibility', 'community');

                if ($membership) {
                    $query->orWhere(function ($family) use ($membership) {
                        $family->where('visibility', 'family')
                            ->where('family_id', $membership->family_id);
                    });
                }
            });

        return [
            'posts' => $myPosts()->count(),
            'likes_received' => PostLike::whereIn('post_id', $myPosts()->select('id'))->count(),
        ];
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
    // สมัครด้วย Google / LINE / Facebook (ยังไม่มีรหัสผ่าน) → ตั้งรหัสใหม่ได้เลย
    public function updatePassword(Request $request)
    {
        $user = $request->user();

        $hadPassword = $user->hasPassword();

        $validated = $request->validate([
            'current_password' => [$hadPassword ? 'required' : 'nullable', 'string'],
            'password' => [
                'required',
                'string',
                'min:8',
                'confirmed',
            ],
        ]);

        if ($hadPassword && !Hash::check(
            (string) $validated['current_password'],
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
            'message' => $hadPassword
                ? 'เปลี่ยนรหัสผ่านเรียบร้อยแล้ว'
                : 'ตั้งรหัสผ่านเรียบร้อยแล้ว ใช้เข้าสู่ระบบด้วยอีเมลได้แล้ว',
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
            'has_password' => $user->hasPassword(),
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
