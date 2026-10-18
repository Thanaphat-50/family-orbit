<?php

namespace App\Http\Controllers;

use App\Models\Shop;
use App\Support\MediaStorage;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use RuntimeException;
use Throwable;

// =======================================================
// ร้านของฉัน (ฝั่งผู้ขาย)
// - สมัครเปิดร้าน → รอ Admin อนุมัติ
// - แก้ไขข้อมูลร้าน (ร้านที่ไม่ผ่าน แก้แล้วส่งตรวจใหม่)
// =======================================================

class MyShopController extends Controller
{
    // =====================================================
    // GET /api/my-shop
    // ยังไม่มีร้าน → shop = null
    // =====================================================

    public function show(Request $request)
    {
        $shop = Shop::where('user_id', $request->user()->id)->first();

        return response()->json([
            'status' => true,
            'shop' => $shop ? $this->payload($shop) : null,
        ]);
    }

    // =====================================================
    // POST /api/my-shop (multipart)
    // สมัครเปิดร้าน ต้องยอมรับกฎผู้ขาย (accept_terms)
    // =====================================================

    public function store(Request $request)
    {
        $user = $request->user();

        if (Shop::where('user_id', $user->id)->exists()) {
            return $this->alreadyHasShop();
        }

        $data = $request->validate(
            $this->rules() + ['accept_terms' => 'accepted'],
            $this->messages()
        );

        $logoPath = $this->storeLogo($request->file('logo'), $user->id);

        if ($logoPath === false) {
            return $this->uploadFailed();
        }

        try {
            $shop = Shop::create([
                ...$this->shopFields($data),
                'user_id' => $user->id,
                'logo_path' => $logoPath,
                'status' => Shop::STATUS_PENDING,
                'terms_accepted_at' => now(),
            ]);
        } catch (UniqueConstraintViolationException) {
            // กดส่งซ้ำพร้อมกัน 2 ครั้ง
            MediaStorage::delete([$logoPath]);

            return $this->alreadyHasShop();
        } catch (Throwable $e) {
            MediaStorage::delete([$logoPath]);

            throw $e;
        }

        return response()->json([
            'status' => true,
            'message' => 'ส่งคำขอเปิดร้านแล้ว รอผู้ดูแลตรวจสอบ',
            'shop' => $this->payload($shop),
        ], 201);
    }

    // =====================================================
    // POST /api/my-shop/update (multipart)
    // logo = เปลี่ยนโลโก้, remove_logo = 1 ลบโลโก้
    // =====================================================

    public function update(Request $request)
    {
        $user = $request->user();

        $shop = Shop::where('user_id', $user->id)->first();

        if (!$shop) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่มีร้าน',
            ], 404);
        }

        $data = $request->validate(
            $this->rules() + ['remove_logo' => 'nullable|boolean'],
            $this->messages()
        );

        $newLogo = $this->storeLogo($request->file('logo'), $user->id);

        if ($newLogo === false) {
            return $this->uploadFailed();
        }

        $oldLogo = $shop->logo_path;

        $shop->fill($this->shopFields($data));

        if ($newLogo) {
            $shop->logo_path = $newLogo;
        } elseif ($request->boolean('remove_logo')) {
            $shop->logo_path = null;
        }

        // ร้านที่ไม่ผ่าน: แก้ไขแล้วถือว่าส่งตรวจใหม่
        $resubmitted = $shop->status === Shop::STATUS_REJECTED;

        if ($resubmitted) {
            $shop->status = Shop::STATUS_PENDING;
            $shop->status_reason = null;
        }

        try {
            $shop->save();
        } catch (Throwable $e) {
            MediaStorage::delete([$newLogo]);

            throw $e;
        }

        // ลบโลโก้เก่าหลังบันทึกสำเร็จ
        if ($oldLogo && $oldLogo !== $shop->logo_path) {
            MediaStorage::delete([$oldLogo]);
        }

        return response()->json([
            'status' => true,
            'message' => $resubmitted
                ? 'ส่งข้อมูลร้านให้ตรวจสอบอีกครั้งแล้ว'
                : 'บันทึกข้อมูลร้านแล้ว',
            'shop' => $this->payload($shop),
        ]);
    }

    // =====================================================
    // HELPERS
    // =====================================================

    private function rules(): array
    {
        return [
            'name' => 'required|string|max:80',
            'description' => 'nullable|string|max:1000',
            'category' => ['required', Rule::in(array_keys(config('market.categories')))],
            'phone' => ['required', 'string', 'regex:/^\+?[0-9][0-9\s\-]{7,18}$/'],
            'line_id' => ['nullable', 'string', 'max:50', 'regex:/^@?[A-Za-z0-9._\-]+$/'],
            'province' => ['required', Rule::in(config('market.provinces'))],
            'district' => 'nullable|string|max:80',
            'logo' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:4096',
        ];
    }

    private function messages(): array
    {
        return [
            'name.required' => 'กรุณาใส่ชื่อร้าน',
            'name.max' => 'ชื่อร้านยาวได้ไม่เกิน 80 ตัวอักษร',
            'description.max' => 'คำอธิบายร้านยาวได้ไม่เกิน 1,000 ตัวอักษร',
            'category.*' => 'กรุณาเลือกหมวดของร้าน',
            'phone.required' => 'กรุณาใส่เบอร์โทร',
            'phone.regex' => 'เบอร์โทรไม่ถูกต้อง',
            'line_id.regex' => 'LINE ID ใช้ได้เฉพาะตัวอักษรอังกฤษ ตัวเลข และ . _ - @',
            'line_id.max' => 'LINE ID ยาวได้ไม่เกิน 50 ตัวอักษร',
            'province.*' => 'กรุณาเลือกจังหวัด',
            'district.max' => 'อำเภอ/เขต ยาวได้ไม่เกิน 80 ตัวอักษร',
            'logo.*' => 'โลโก้ต้องเป็นรูป JPG, PNG หรือ WEBP ไม่เกิน 4 MB',
            'accept_terms.accepted' => 'กรุณายอมรับกฎผู้ขายก่อนเปิดร้าน',
        ];
    }

    private function shopFields(array $data): array
    {
        return [
            'name' => trim($data['name']),
            'description' => $data['description'] ?? null,
            'category' => $data['category'],
            // เก็บเบอร์แบบตัวเลขล้วน
            'phone' => preg_replace('/[\s\-]/', '', $data['phone']),
            'line_id' => $data['line_id'] ?? null,
            'province' => $data['province'],
            'district' => $data['district'] ?? null,
        ];
    }

    // คืน path ของโลโก้ / null ถ้าไม่ได้ส่งมา / false ถ้าเก็บไฟล์ไม่สำเร็จ
    private function storeLogo(?UploadedFile $file, int $userId): string|null|false
    {
        if (!$file) {
            return null;
        }

        try {
            $path = $file->store('shop_logos', MediaStorage::disk());

            if (!$path) {
                throw new RuntimeException('Could not store the shop logo.');
            }

            return $path;
        } catch (Throwable $e) {
            Log::error('Shop logo upload failed', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    private function payload(Shop $shop): array
    {
        return [
            ...$shop->toArray(),
            'status_label' => Shop::STATUS_LABELS[$shop->status] ?? $shop->status,
        ];
    }

    private function alreadyHasShop()
    {
        return response()->json([
            'status' => false,
            'message' => 'คุณมีร้านอยู่แล้ว (1 บัญชีเปิดได้ 1 ร้าน)',
        ], 409);
    }

    private function uploadFailed()
    {
        return response()->json([
            'status' => false,
            'message' => 'อัปโหลดโลโก้ไม่สำเร็จ กรุณาลองอีกครั้ง',
        ], 500);
    }
}
