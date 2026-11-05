<?php

namespace App\Http\Controllers;

use App\Models\Shop;
use App\Support\MarketVideo;
use App\Support\MediaStorage;
use App\Support\PromptPay;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use RuntimeException;
use Throwable;

// =======================================================
// ร้านของฉัน (ฝั่งผู้ขาย)
// - เปิดร้านได้ทันที ไม่ต้องรอ Admin อนุมัติ
//   (ระบบตรวจคำต้องห้ามอัตโนมัติ → แจ้งผู้ดูแล ดู App\Services\MarketScreening)
// - แก้ไขข้อมูลร้าน (ร้านที่ไม่ผ่านแบบเดิม แก้แล้วเปิดขายเลย)
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
            $this->rules($request) + ['accept_terms' => 'accepted'],
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
                'status' => Shop::STATUS_ACTIVE,
                'approved_at' => now(),
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
            'message' => $shop->status === Shop::STATUS_ACTIVE
                ? 'เปิดร้านแล้ว ลงสินค้าได้เลย'
                : Shop::AUTO_SCREEN_REASON,
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
            $this->rules($request) + ['remove_logo' => 'nullable|boolean'],
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

        // ร้านที่ไม่ผ่าน/รออนุมัติแบบเดิม: แก้ไขแล้วเปิดขายเลย (ร้านที่ถูกระงับยังปิดอยู่)
        $resubmitted = in_array($shop->status, [Shop::STATUS_REJECTED, Shop::STATUS_PENDING], true);

        if ($resubmitted) {
            $shop->status = Shop::STATUS_ACTIVE;
            $shop->status_reason = null;
            $shop->approved_at ??= now();
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
                ? 'บันทึกแล้ว ร้านเปิดขายแล้ว'
                : 'บันทึกข้อมูลร้านแล้ว',
            'shop' => $this->payload($shop),
        ]);
    }

    // =====================================================
    // HELPERS
    // =====================================================

    private function rules(Request $request): array
    {
        $methods = (array) $request->input('payment_methods', []);

        $usesPromptPay = in_array('promptpay', $methods, true);
        $usesBank = in_array('bank', $methods, true);

        return [
            // payment_settings = 1 → บันทึกวิธีรับเงินด้วย (แอปเวอร์ชันเก่าไม่ส่ง = ไม่เปลี่ยน)
            'payment_settings' => 'nullable|boolean',
            'payment_methods' => 'nullable|array',
            'payment_methods.*' => ['distinct', Rule::in(array_keys(config('market.payment_methods')))],
            // ตรวจรูปแบบเฉพาะวิธีที่เลือก (ที่ไม่ได้เลือกเก็บค่าเดิมไว้ เปิดใหม่ไม่ต้องพิมพ์ซ้ำ)
            'promptpay_id' => [
                Rule::requiredIf($usesPromptPay),
                'nullable',
                'string',
                'max:30',
                function (string $attribute, mixed $value, \Closure $fail) use ($usesPromptPay) {
                    if ($usesPromptPay && filled($value) && !PromptPay::isValidId($value)) {
                        $fail('พร้อมเพย์ต้องเป็นเบอร์มือถือ 10 หลัก หรือเลขบัตรประชาชน 13 หลัก');
                    }
                },
            ],
            'bank_name' => [
                Rule::requiredIf($usesBank),
                'nullable',
                ...($usesBank ? [Rule::in(config('market.banks'))] : ['string', 'max:60']),
            ],
            'bank_account_number' => [
                Rule::requiredIf($usesBank),
                'nullable',
                'string',
                ...($usesBank ? ['regex:/^[0-9][0-9\s\-]{8,20}$/'] : ['max:30']),
            ],
            'bank_account_name' => [Rule::requiredIf($usesPromptPay || $usesBank), 'nullable', 'string', 'max:100'],

            'name' => 'required|string|max:80',
            'description' => 'nullable|string|max:1000',
            'category' => ['required', Rule::in(array_keys(config('market.categories')))],
            'phone' => ['required', 'string', 'regex:/^\+?[0-9][0-9\s\-]{7,18}$/'],
            'line_id' => ['nullable', 'string', 'max:50', 'regex:/^@?[A-Za-z0-9._\-]+$/'],
            'province' => ['required', Rule::in(config('market.provinces'))],
            'district' => 'nullable|string|max:80',
            'opening_hours' => 'nullable|string|max:200',
            'delivery_methods' => 'nullable|array',
            'delivery_methods.*' => ['distinct', Rule::in(array_keys(config('market.delivery_methods')))],
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
            'opening_hours.max' => 'เวลาเปิด-ปิดยาวได้ไม่เกิน 200 ตัวอักษร',
            'delivery_methods.*' => 'วิธีรับสินค้าไม่ถูกต้อง',
            'payment_methods.*' => 'วิธีรับเงินไม่ถูกต้อง',
            'promptpay_id.required' => 'กรุณาใส่เบอร์หรือเลขพร้อมเพย์ของร้าน',
            'bank_name.*' => 'กรุณาเลือกธนาคาร',
            'bank_account_number.required' => 'กรุณาใส่เลขบัญชี',
            'bank_account_number.regex' => 'เลขบัญชีไม่ถูกต้อง',
            'bank_account_name.required' => 'กรุณาใส่ชื่อบัญชีผู้รับเงิน',
            'bank_account_name.max' => 'ชื่อบัญชียาวได้ไม่เกิน 100 ตัวอักษร',
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
            'opening_hours' => filled($data['opening_hours'] ?? null) ? trim($data['opening_hours']) : null,
            'delivery_methods' => array_values(array_unique($data['delivery_methods'] ?? [])) ?: null,
            ...(!empty($data['payment_settings']) ? [
                'payment_methods' => array_values(array_unique($data['payment_methods'] ?? [])) ?: null,
                // เก็บแบบตัวเลขล้วน
                'promptpay_id' => filled($data['promptpay_id'] ?? null)
                    ? preg_replace('/\D/', '', $data['promptpay_id'])
                    : null,
                'bank_name' => $data['bank_name'] ?? null,
                'bank_account_number' => filled($data['bank_account_number'] ?? null)
                    ? preg_replace('/\D/', '', $data['bank_account_number'])
                    : null,
                'bank_account_name' => filled($data['bank_account_name'] ?? null)
                    ? trim($data['bank_account_name'])
                    : null,
            ] : []),
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
            ...$shop->paymentSettings(),
            'status_label' => Shop::STATUS_LABELS[$shop->status] ?? $shop->status,
            'images' => $shop->images()->get(),
            'max_images' => (int) config('market.max_shop_images'),
        ];
    }

    // =====================================================
    // POST /api/my-shop/media (multipart)
    // รูปหน้าร้าน: images[] เพิ่ม / remove_image_ids[] ลบ
    // วิดีโอแนะนำร้าน: video + video_thumbnail แทนของเดิม / remove_video=1 ลบ
    // =====================================================

    public function updateMedia(Request $request)
    {
        $shop = Shop::where('user_id', $request->user()->id)->first();

        if (!$shop) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่มีร้าน',
            ], 404);
        }

        if ($shop->status === Shop::STATUS_SUSPENDED) {
            return response()->json([
                'status' => false,
                'message' => 'ร้านถูกระงับ แก้ไขรูปและวิดีโอไม่ได้',
            ], 403);
        }

        $max = (int) config('market.max_shop_images');

        $data = $request->validate([
            'images' => "nullable|array|max:{$max}",
            'images.*' => 'image|mimes:jpg,jpeg,png,webp|max:5120',
            'remove_image_ids' => 'nullable|array',
            'remove_image_ids.*' => 'integer',
            'remove_video' => 'nullable|boolean',
            ...MarketVideo::rules(),
        ], [
            'images.max' => "รูปหน้าร้านได้ไม่เกิน {$max} รูป",
            'images.*' => 'รูปต้องเป็น JPG, PNG หรือ WEBP ไม่เกิน 5 MB',
            ...MarketVideo::messages(),
        ]);

        $removeIds = collect($data['remove_image_ids'] ?? [])->map(fn ($id) => (int) $id);

        $removed = $shop->images()->whereIn('id', $removeIds)->get();

        $newFiles = $request->file('images', []);

        if ($shop->images()->count() - $removed->count() + count($newFiles) > $max) {
            return response()->json([
                'status' => false,
                'message' => "รูปหน้าร้านได้ไม่เกิน {$max} รูป",
            ], 422);
        }

        $newPaths = [];
        $video = null;

        try {
            foreach ($newFiles as $file) {
                $newPaths[] = $file->store('shop_images/' . $shop->id, MediaStorage::disk())
                    ?: throw new RuntimeException('Could not store the shop image.');
            }

            if ($request->hasFile('video')) {
                $video = MarketVideo::store($request, 'shop_videos/' . $shop->id);
            }
        } catch (Throwable $e) {
            MediaStorage::delete($newPaths);

            Log::error('Shop media upload failed', [
                'shop_id' => $shop->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'status' => false,
                'message' => 'อัปโหลดรูปหรือวิดีโอไม่สำเร็จ กรุณาลองอีกครั้ง',
            ], 500);
        }

        $oldPaths = $removed->pluck('path')->all();

        if ($video || $request->boolean('remove_video')) {
            $oldPaths[] = $shop->video_path;
            $oldPaths[] = $shop->video_thumbnail_path;
        }

        DB::transaction(function () use ($shop, $removed, $newPaths, $video, $request) {
            $shop->images()->whereKey($removed->pluck('id'))->delete();

            $sort = (int) $shop->images()->max('sort');

            foreach ($newPaths as $path) {
                $shop->images()->create(['path' => $path, 'sort' => ++$sort]);
            }

            if ($video) {
                $shop->forceFill($video)->save();
            } elseif ($request->boolean('remove_video')) {
                $shop->forceFill(['video_path' => null, 'video_thumbnail_path' => null])->save();
            }
        });

        DB::afterCommit(fn () => MediaStorage::delete($oldPaths));

        return response()->json([
            'status' => true,
            'message' => 'บันทึกรูปและวิดีโอร้านแล้ว',
            'shop' => $this->payload($shop->refresh()),
        ]);
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
