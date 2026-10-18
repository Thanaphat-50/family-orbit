<?php

namespace App\Services;

use App\Models\Family;
use App\Models\FamilyMember;
use App\Models\PostImage;
use App\Models\User;
use App\Support\MediaStorage;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use RuntimeException;
use Throwable;

// =======================================================
// ลบบัญชีผู้ใช้และข้อมูลทั้งหมด
// ใช้ทั้งจากแอป (DELETE /api/account) และหน้าเว็บ (/account/delete)
// =======================================================

class AccountDeletionService
{
    // =====================================================
    // ตรวจว่าลบได้หรือไม่
    // คืนข้อความเหตุผลถ้าลบไม่ได้ / null ถ้าลบได้
    // =====================================================

    public function blockingReason(User $user): ?string
    {
        $family = Family::where('owner_id', $user->id)->first();

        if (!$family) {
            return null;
        }

        $hasOtherMembers = FamilyMember::where('family_id', $family->id)
            ->where('user_id', '!=', $user->id)
            ->exists();

        return $hasOtherMembers
            ? 'คุณเป็น Owner ของครอบครัวที่ยังมีสมาชิกอยู่ '
                . 'กรุณาโอนสิทธิ์ Owner ให้สมาชิกคนอื่นก่อนลบบัญชี'
            : null;
    }

    // =====================================================
    // ลบบัญชี
    //
    // ลบโดยอัตโนมัติผ่าน Foreign Key (cascade):
    // สมาชิกครอบครัว, ตำแหน่ง, โพสต์, ความคิดเห็น, กิจกรรม,
    // การแจ้งเตือน, รายงาน และการบล็อก
    // =====================================================

    public function delete(User $user): void
    {
        $reason = $this->blockingReason($user);

        if ($reason !== null) {
            throw new RuntimeException($reason);
        }

        $photoPath = $user->profile_photo;

        // ไฟล์รูปในโพสต์ที่จะถูกลบตาม cascade:
        // โพสต์ของผู้ใช้ + โพสต์ของครอบครัวที่ผู้ใช้เป็น Owner คนเดียว
        $imagePaths = PostImage::whereHas('post', function ($posts) use ($user) {
            $posts->where('user_id', $user->id)
                ->orWhereIn(
                    'family_id',
                    Family::where('owner_id', $user->id)->select('id')
                );
        })->pluck('path')->all();

        DB::transaction(function () use ($user) {
            // Owner คนเดียวของครอบครัว → ลบครอบครัวด้วย
            Family::where('owner_id', $user->id)->delete();

            // Token ไม่มี Foreign Key ต้องลบเอง
            $user->tokens()->delete();

            $user->delete();
        });

        // ลบไฟล์รูปในโพสต์หลังลบข้อมูลสำเร็จแล้ว
        MediaStorage::delete($imagePaths);

        // ลบรูปโปรไฟล์หลังลบข้อมูลสำเร็จแล้ว
        if ($photoPath) {
            try {
                Storage::disk(User::profilePhotoDisk())->delete($photoPath);
            } catch (Throwable $e) {
                Log::warning('Could not delete profile photo of deleted account', [
                    'error' => $e->getMessage(),
                ]);
            }
        }
    }
}
