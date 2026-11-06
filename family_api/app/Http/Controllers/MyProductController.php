<?php

namespace App\Http\Controllers;

use App\Models\Product;
use App\Models\ProductImage;
use App\Models\ProductVariant;
use App\Models\Shop;
use App\Support\MarketVideo;
use App\Support\MediaStorage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use Throwable;

// =======================================================
// สินค้าในร้านของฉัน (ฝั่งผู้ขาย)
// - ช่วงเปิดร้านฟรี: ร้านละไม่เกิน 30 ชิ้น, ชิ้นละ 1–5 รูป
// - ร้านที่ถูกระงับ เพิ่ม/แก้ไขสินค้าไม่ได้ (ซ่อน/ลบได้)
// =======================================================

class MyProductController extends Controller
{
    // =====================================================
    // GET /api/my-shop/products
    // =====================================================

    public function index(Request $request)
    {
        $shop = $this->myShop($request);

        if (!$shop) {
            return $this->noShop();
        }

        return response()->json([
            'status' => true,
            'products' => $shop->products()->with('images')->latest()->get()
                ->map(fn (Product $product) => $this->sellerPayload($product))
                ->values(),
            'limit' => (int) config('market.max_products_per_shop'),
            'max_images' => (int) config('market.max_images_per_product'),
        ]);
    }

    // =====================================================
    // POST /api/my-shop/products (multipart, images[] 1–5 รูป)
    // =====================================================

    public function store(Request $request)
    {
        $shop = $this->myShop($request);

        if (!$shop) {
            return $this->noShop();
        }

        if ($shop->status === Shop::STATUS_SUSPENDED) {
            return $this->suspended();
        }

        $maxImages = (int) config('market.max_images_per_product');

        $data = $request->validate($this->rules() + [
            'images' => "required|array|min:1|max:{$maxImages}",
            'images.*' => 'image|mimes:jpg,jpeg,png,webp|max:4096',
        ], $this->messages());

        $limit = (int) config('market.max_products_per_shop');

        if ($shop->products()->count() >= $limit) {
            return response()->json([
                'status' => false,
                'message' => "ลงสินค้าได้สูงสุด {$limit} ชิ้น ลบสินค้าเก่าก่อนเพิ่มใหม่",
            ], 422);
        }

        $paths = $this->storeImages($request->file('images', []), $shop);

        if ($paths === null) {
            return $this->uploadFailed();
        }

        try {
            $product = DB::transaction(function () use ($shop, $data, $paths) {
                $product = $shop->products()->create([
                    ...$this->productFields($data),
                    'status' => Product::STATUS_ACTIVE,
                ]);

                foreach ($paths as $index => $path) {
                    $product->images()->create([
                        'path' => $path,
                        'sort' => $index,
                    ]);
                }

                if (!empty($data['variants_present'])) {
                    $this->syncVariants($product, $data['variants'] ?? []);
                }

                return $product;
            });
        } catch (Throwable $e) {
            MediaStorage::delete($paths);

            throw $e;
        }

        return response()->json([
            'status' => true,
            'message' => $product->hidden_at !== null
                ? 'เพิ่มสินค้าแล้ว แต่ระบบพบคำที่อาจผิดกฎ สินค้าถูกซ่อนไว้รอทีมงานตรวจสอบ'
                : 'เพิ่มสินค้าแล้ว',
            'product' => $this->sellerPayload($product->load('images')),
        ], 201);
    }

    // =====================================================
    // POST /api/my-shop/products/{product}/update (multipart)
    // images[] = รูปใหม่ที่เพิ่ม, remove_image_ids[] = รูปเดิมที่เอาออก
    // =====================================================

    public function update(Request $request, Product $product)
    {
        $shop = $this->myShop($request);

        if (!$shop || (int) $product->shop_id !== (int) $shop->id) {
            return $this->notFound();
        }

        if ($shop->status === Shop::STATUS_SUSPENDED) {
            return $this->suspended();
        }

        $maxImages = (int) config('market.max_images_per_product');

        $data = $request->validate($this->rules() + [
            'images' => "nullable|array|max:{$maxImages}",
            'images.*' => 'image|mimes:jpg,jpeg,png,webp|max:4096',
            'remove_image_ids' => 'nullable|array',
            'remove_image_ids.*' => 'integer',
        ], $this->messages());

        $removeIds = collect($data['remove_image_ids'] ?? [])->map(fn ($id) => (int) $id);

        [$removed, $kept] = $product->images->partition(
            fn (ProductImage $image) => $removeIds->contains($image->id)
        );

        $newFiles = $request->file('images', []);

        $total = $kept->count() + count($newFiles);

        if ($total < 1 || $total > $maxImages) {
            return response()->json([
                'status' => false,
                'message' => $total < 1
                    ? 'สินค้าต้องมีรูปอย่างน้อย 1 รูป'
                    : "สินค้าแต่ละชิ้นมีรูปได้สูงสุด {$maxImages} รูป",
            ], 422);
        }

        $newPaths = $this->storeImages($newFiles, $shop);

        if ($newPaths === null) {
            return $this->uploadFailed();
        }

        try {
            DB::transaction(function () use ($product, $data, $removed, $kept, $newPaths) {
                $product->fill($this->productFields($data))->save();

                if (!empty($data['variants_present'])) {
                    $this->syncVariants($product, $data['variants'] ?? []);
                }

                ProductImage::whereIn('id', $removed->pluck('id'))->delete();

                // เรียงใหม่: รูปเดิมที่เก็บไว้ก่อน แล้วต่อด้วยรูปใหม่
                $sort = 0;

                foreach ($kept as $image) {
                    $image->update(['sort' => $sort++]);
                }

                foreach ($newPaths as $path) {
                    $product->images()->create([
                        'path' => $path,
                        'sort' => $sort++,
                    ]);
                }
            });
        } catch (Throwable $e) {
            MediaStorage::delete($newPaths);

            throw $e;
        }

        // ลบไฟล์รูปที่เอาออกหลังบันทึกสำเร็จ
        MediaStorage::delete($removed->pluck('path')->all());

        return response()->json([
            'status' => true,
            'message' => $product->hidden_at !== null
                ? 'บันทึกแล้ว สินค้าถูกซ่อนไว้รอทีมงานตรวจสอบ'
                : 'บันทึกสินค้าแล้ว',
            'product' => $this->sellerPayload($product->unsetRelation('images')->load('images')),
        ]);
    }

    // =====================================================
    // PATCH /api/my-shop/products/{product}/status
    // status: active (แสดง) / hidden (ซ่อนไว้ก่อน)
    // =====================================================

    public function updateStatus(Request $request, Product $product)
    {
        $shop = $this->myShop($request);

        if (!$shop || (int) $product->shop_id !== (int) $shop->id) {
            return $this->notFound();
        }

        $data = $request->validate([
            'status' => ['required', Rule::in([Product::STATUS_ACTIVE, Product::STATUS_HIDDEN])],
        ]);

        $product->status = $data['status'];
        $product->save();

        return response()->json([
            'status' => true,
            'message' => $product->status === Product::STATUS_HIDDEN
                ? 'ซ่อนสินค้าแล้ว'
                : 'แสดงสินค้าแล้ว',
            'product' => $this->sellerPayload($product->load('images')),
        ]);
    }

    // =====================================================
    // DELETE /api/my-shop/products/{product}
    // =====================================================

    public function destroy(Request $request, Product $product)
    {
        $shop = $this->myShop($request);

        if (!$shop || (int) $product->shop_id !== (int) $shop->id) {
            return $this->notFound();
        }

        $product->delete();

        return response()->json([
            'status' => true,
            'message' => 'ลบสินค้าแล้ว',
        ]);
    }

    // =====================================================
    // POST /api/my-shop/products/{product}/video (multipart video + video_thumbnail)
    // DELETE /api/my-shop/products/{product}/video
    // วิดีโอแนะนำสินค้า (1 คลิปต่อสินค้า แทนของเดิม)
    // =====================================================

    public function updateVideo(Request $request, Product $product)
    {
        $shop = $this->myShop($request);

        if (!$shop || (int) $product->shop_id !== (int) $shop->id) {
            return $this->notFound();
        }

        if ($shop->status === Shop::STATUS_SUSPENDED) {
            return $this->suspended();
        }

        $request->validate(
            ['video' => 'required', ...MarketVideo::rules()],
            ['video.required' => 'กรุณาเลือกวิดีโอ', ...MarketVideo::messages()]
        );

        try {
            $video = MarketVideo::store($request, 'product_videos/' . $shop->id);
        } catch (Throwable $e) {
            Log::error('Product video upload failed', [
                'product_id' => $product->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'status' => false,
                'message' => 'อัปโหลดวิดีโอไม่สำเร็จ กรุณาลองอีกครั้ง',
            ], 500);
        }

        $old = [$product->video_path, $product->video_thumbnail_path];

        $product->forceFill($video)->save();

        MediaStorage::delete($old);

        return response()->json([
            'status' => true,
            'message' => 'บันทึกวิดีโอสินค้าแล้ว',
            'product' => $this->sellerPayload($product->load('images')),
        ]);
    }

    public function destroyVideo(Request $request, Product $product)
    {
        $shop = $this->myShop($request);

        if (!$shop || (int) $product->shop_id !== (int) $shop->id) {
            return $this->notFound();
        }

        $old = [$product->video_path, $product->video_thumbnail_path];

        $product->forceFill(['video_path' => null, 'video_thumbnail_path' => null])->save();

        MediaStorage::delete($old);

        return response()->json([
            'status' => true,
            'message' => 'ลบวิดีโอสินค้าแล้ว',
            'product' => $this->sellerPayload($product->load('images')),
        ]);
    }

    // =====================================================
    // HELPERS
    // =====================================================

    // ข้อมูลสินค้าฝั่งผู้ขาย + วิดีโอ + สถานะช่องแนะนำ
    private function sellerPayload(Product $product): array
    {
        $product->loadMissing('variants');

        return [
            ...$product->toArray(),
            'variants' => $product->variants
                ->map(fn (ProductVariant $variant) => $variant->only(['id', 'name', 'price', 'stock']))
                ->values(),
            'video_url' => $product->video_url,
            'video_thumbnail_url' => $product->video_thumbnail_url,
            'featured_until' => $product->featured_until,
            'is_featured' => $product->isFeatured(),
        ];
    }

    private function myShop(Request $request): ?Shop
    {
        return Shop::where('user_id', $request->user()->id)->first();
    }

    private function rules(): array
    {
        return [
            'title' => 'required|string|max:120',
            'description' => 'nullable|string|max:2000',
            'price' => 'nullable|numeric|min:0|max:9999999',
            'category' => ['required', Rule::in(array_keys(config('market.categories')))],
            // ไม่ส่งมา (แอปเวอร์ชันเก่า) = ไม่เปลี่ยน
            'stock' => 'sometimes|required|integer|min:0|max:' . config('market.max_stock'),
            'shipping_fee' => 'nullable|numeric|min:0|max:99999',
            'card_media' => ['sometimes', Rule::in(['image', 'video'])],
            // variants_present = 1 → บันทึกตัวเลือกสินค้าด้วย (ไม่ส่ง = ไม่เปลี่ยน)
            'variants_present' => 'nullable|boolean',
            'option_name' => 'nullable|string|max:40',
            'variants' => 'nullable|array|max:20',
            'variants.*.id' => 'nullable|integer',
            'variants.*.name' => 'required|string|max:60|distinct',
            'variants.*.price' => 'nullable|numeric|min:0|max:9999999',
            'variants.*.stock' => 'required|integer|min:0|max:' . config('market.max_stock'),
        ];
    }

    private function messages(): array
    {
        $maxImages = (int) config('market.max_images_per_product');

        return [
            'title.required' => 'กรุณาใส่ชื่อสินค้า',
            'title.max' => 'ชื่อสินค้ายาวได้ไม่เกิน 120 ตัวอักษร',
            'description.max' => 'รายละเอียดยาวได้ไม่เกิน 2,000 ตัวอักษร',
            'price.*' => 'ราคาต้องเป็นตัวเลข 0 – 9,999,999 บาท',
            'category.*' => 'กรุณาเลือกหมวดสินค้า',
            'stock.*' => 'จำนวนในสต็อกต้องเป็นตัวเลข 0 – ' . number_format(config('market.max_stock')),
            'shipping_fee.*' => 'ค่าส่งต้องเป็นตัวเลข 0 – 99,999 บาท',
            'card_media.*' => 'เลือกหน้าปกการ์ดเป็นรูปหรือวิดีโอ',
            'option_name.*' => 'ชื่อหัวข้อตัวเลือกยาวได้ไม่เกิน 40 ตัวอักษร',
            'variants.max' => 'ตัวเลือกสินค้าได้ไม่เกิน 20 แบบ',
            'variants.*.name.required' => 'กรุณาใส่ชื่อตัวเลือกให้ครบ',
            'variants.*.name.max' => 'ชื่อตัวเลือกยาวได้ไม่เกิน 60 ตัวอักษร',
            'variants.*.name.distinct' => 'ชื่อตัวเลือกซ้ำกัน',
            'variants.*.price.*' => 'ราคาตัวเลือกต้องเป็นตัวเลข',
            'variants.*.stock.*' => 'สต็อกของตัวเลือกต้องเป็นตัวเลข 0 ขึ้นไป',
            'images.required' => 'กรุณาเพิ่มรูปสินค้าอย่างน้อย 1 รูป',
            'images.min' => 'กรุณาเพิ่มรูปสินค้าอย่างน้อย 1 รูป',
            'images.max' => "สินค้าแต่ละชิ้นมีรูปได้สูงสุด {$maxImages} รูป",
            'images.*.image' => 'รองรับเฉพาะรูป JPG, PNG หรือ WEBP',
            'images.*.mimes' => 'รองรับเฉพาะรูป JPG, PNG หรือ WEBP',
            'images.*.max' => 'รูปแต่ละรูปต้องมีขนาดไม่เกิน 4 MB',
            'images.*.uploaded' => 'อัปโหลดรูปไม่สำเร็จ กรุณาลองอีกครั้ง',
        ];
    }

    private function productFields(array $data): array
    {
        return [
            'title' => trim($data['title']),
            'description' => $data['description'] ?? null,
            'price' => $data['price'] ?? null,
            'category' => $data['category'],
            ...array_intersect_key($data, array_flip(['stock', 'shipping_fee', 'card_media'])),
            ...(!empty($data['variants_present']) ? ['option_name' => filled($data['option_name'] ?? null) ? trim($data['option_name']) : null] : []),
        ];
    }

    // ตัวเลือกสินค้า: แก้ตัวเดิม (มี id) / เพิ่มใหม่ / ลบตัวที่ไม่ได้ส่งมา
    // มีตัวเลือก → สต็อกรวมของสินค้า = ผลรวมสต็อกของตัวเลือก
    private function syncVariants(Product $product, array $rows): void
    {
        $keep = [];

        foreach (array_values($rows) as $index => $row) {
            $variant = isset($row['id'])
                ? $product->variants()->whereKey((int) $row['id'])->first()
                : null;

            $variant ??= new ProductVariant(['product_id' => $product->id]);

            $variant->fill([
                'name' => trim($row['name']),
                'price' => $row['price'] ?? null,
                'stock' => (int) $row['stock'],
                'sort' => $index,
            ])->save();

            $keep[] = $variant->id;
        }

        $product->variants()->whereNotIn('id', $keep)->delete();

        $product->unsetRelation('variants');

        if ($keep === []) {
            return;
        }

        $product->syncStockFromVariants();

        // ไม่ได้ตั้งราคาหลัก → ใช้ราคาต่ำสุดของตัวเลือก (การ์ดสินค้าแสดงราคานี้)
        if ($product->price === null) {
            $min = $product->load('variants')->priceRange()['min'] ?? null;

            if ($min !== null) {
                $product->forceFill(['price' => $min])->saveQuietly();
            }
        }
    }

    // คืน path ที่เก็บแล้ว / null ถ้าเก็บไฟล์ไม่สำเร็จ
    private function storeImages(array $files, Shop $shop): ?array
    {
        try {
            return MediaStorage::storeAll($files, 'product_images');
        } catch (Throwable $e) {
            Log::error('Product image upload failed', [
                'shop_id' => $shop->id,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    private function noShop()
    {
        return response()->json([
            'status' => false,
            'message' => 'คุณยังไม่มีร้าน',
        ], 404);
    }

    private function notFound()
    {
        return response()->json([
            'status' => false,
            'message' => 'ไม่พบสินค้านี้ในร้านของคุณ',
        ], 404);
    }

    private function suspended()
    {
        return response()->json([
            'status' => false,
            'message' => 'ร้านถูกระงับ ไม่สามารถเพิ่มหรือแก้ไขสินค้าได้',
        ], 403);
    }

    private function uploadFailed()
    {
        return response()->json([
            'status' => false,
            'message' => 'อัปโหลดรูปไม่สำเร็จ กรุณาลองอีกครั้ง',
        ], 500);
    }
}
