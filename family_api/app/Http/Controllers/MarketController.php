<?php

namespace App\Http\Controllers;

use App\Models\Product;
use App\Models\ProductReport;
use App\Models\Shop;
use App\Models\ShopReport;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

// =======================================================
// ตลาด (ฝั่งผู้ซื้อ)
// - เห็นเฉพาะสินค้าที่แสดงอยู่ของร้านที่เปิดขาย
// - ไม่แสดงสินค้าที่เรารายงานแล้ว และร้านของคนที่เราบล็อก
// =======================================================

class MarketController extends Controller
{
    private const PAGE_SIZE = 20;

    // =====================================================
    // GET /api/market/products?q=&category=&province=&page=
    // =====================================================

    public function products(Request $request)
    {
        $filters = $request->validate([
            'q' => 'nullable|string|max:100',
            'category' => ['nullable', Rule::in(array_keys(config('market.categories')))],
            'province' => ['nullable', Rule::in(config('market.provinces'))],
        ]);

        $user = $request->user();

        $term = trim($filters['q'] ?? '');

        $paginator = $this->visibleProductsFor($user)
            ->when($term !== '', function (Builder $query) use ($term) {
                $like = '%' . addcslashes($term, '%_\\') . '%';

                $query->where(function (Builder $match) use ($like) {
                    $match->where('title', 'like', $like)
                        ->orWhere('description', 'like', $like)
                        ->orWhereHas('shop', fn ($shops) => $shops->where('name', 'like', $like));
                });
            })
            ->when($filters['category'] ?? null, fn ($query, $category) => $query->where('category', $category))
            ->when(
                $filters['province'] ?? null,
                fn ($query, $province) => $query->whereHas('shop', fn ($shops) => $shops->where('province', $province))
            )
            ->with(['images', 'shop'])
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->simplePaginate(self::PAGE_SIZE);

        return response()->json([
            'status' => true,
            'products' => collect($paginator->items())
                ->map(fn (Product $product) => $this->productCard($product))
                ->values(),
            'page' => $paginator->currentPage(),
            'has_more' => $paginator->hasMorePages(),
        ]);
    }

    // =====================================================
    // GET /api/market/products/{product}
    // เจ้าของร้านดูสินค้าตัวเองได้เสมอ (ดูตัวอย่างก่อนร้านเปิด)
    // =====================================================

    public function showProduct(Request $request, Product $product)
    {
        $user = $request->user();

        $product->load(['images', 'shop']);

        $isMine = (int) $product->shop->user_id === (int) $user->id;

        if (!$isMine && !$this->visibleProductsFor($user)->whereKey($product->id)->exists()) {
            return $this->productNotFound();
        }

        // นับยอดเข้าชม (ไม่นับเจ้าของร้าน และไม่แตะ updated_at)
        if (!$isMine) {
            Product::whereKey($product->id)->toBase()->increment('views');
        }

        return response()->json([
            'status' => true,
            'product' => [
                ...$product->only(['id', 'title', 'description', 'price', 'category', 'status', 'created_at']),
                'images' => $product->images,
                'is_mine' => $isMine,
            ],
            'shop' => $this->shopPayload($product->shop),
        ]);
    }

    // =====================================================
    // GET /api/market/featured
    // ร้านแนะนำ (ร้านที่เช่าพื้นที่) สำหรับแบนเนอร์ด้านบนตลาด
    // - สลับลำดับทุกครั้ง ให้ทุกร้านที่เช่ามีโอกาสขึ้นก่อนเท่ากัน
    // - ส่งรูปสินค้าล่าสุดไม่เกิน 3 รูปไปแสดงในแบนเนอร์
    // =====================================================

    public function featured(Request $request)
    {
        $blockedIds = $request->user()->blockedUsers()->pluck('users.id');

        $shops = Shop::featured()
            ->whereNotIn('user_id', $blockedIds)
            ->withCount(['products as products_count' => fn ($products) => $this->onlyShown($products)])
            ->with([
                'products' => fn ($products) => $this->onlyShown($products)->latest(),
                'products.images',
            ])
            ->inRandomOrder()
            ->limit((int) config('market.featured_slots'))
            ->get();

        return response()->json([
            'status' => true,
            'shops' => $shops->map(fn (Shop $shop) => [
                ...$this->shopPayload($shop),
                'products_count' => $shop->products_count,
                'preview_images' => $shop->products
                    ->map(fn (Product $product) => $product->images->first()?->url)
                    ->filter()
                    ->take(3)
                    ->values(),
            ])->values(),
        ]);
    }

    // =====================================================
    // GET /api/market/shops/{shop}
    // ข้อมูลร้าน + สินค้าทั้งหมดที่แสดงอยู่
    // =====================================================

    public function showShop(Request $request, Shop $shop)
    {
        $user = $request->user();

        $isMine = (int) $shop->user_id === (int) $user->id;

        $blocked = $user->blockedUsers()->where('users.id', $shop->user_id)->exists();

        if (!$isMine && (!$shop->isActive() || $blocked)) {
            return response()->json([
                'status' => false,
                'message' => 'ไม่พบร้านนี้ หรือร้านปิดอยู่',
            ], 404);
        }

        $products = $this->onlyShown($shop->products())
            ->whereDoesntHave('reports', fn ($reports) => $reports->where('user_id', $user->id))
            ->with('images')
            ->latest()
            ->get();

        return response()->json([
            'status' => true,
            'shop' => [
                ...$this->shopPayload($shop),
                'is_mine' => $isMine,
            ],
            'products' => $products->map(fn (Product $product) => $this->productCard($product, false))->values(),
        ]);
    }

    // =====================================================
    // POST /api/market/products/{product}/report
    // =====================================================

    public function reportProduct(Request $request, Product $product)
    {
        $data = $this->validateReport($request);

        $user = $request->user();

        if ((int) $product->shop->user_id === (int) $user->id) {
            return $this->cannotReportOwn();
        }

        if (!$this->visibleProductsFor($user)->whereKey($product->id)->exists()) {
            return $this->productNotFound();
        }

        // รายงานซ้ำไม่นับเพิ่ม
        ProductReport::firstOrCreate(
            ['product_id' => $product->id, 'user_id' => $user->id],
            ['reason' => $data['reason'], 'details' => $data['details'] ?? null]
        );

        // ซ่อนอัตโนมัติเมื่อถูกรายงานครบ (รอ Admin ตรวจ)
        if (
            $product->hidden_at === null
            && $product->reports()->count() >= config('market.auto_hide_reports')
        ) {
            $product->hidden_at = now();
            $product->save();
        }

        return response()->json([
            'status' => true,
            'message' => 'ขอบคุณที่รายงาน ผู้ดูแลจะตรวจสอบสินค้านี้',
        ]);
    }

    // =====================================================
    // POST /api/market/shops/{shop}/report
    // =====================================================

    public function reportShop(Request $request, Shop $shop)
    {
        $data = $this->validateReport($request);

        $user = $request->user();

        if ((int) $shop->user_id === (int) $user->id) {
            return $this->cannotReportOwn();
        }

        if (!$shop->isActive()) {
            return response()->json([
                'status' => false,
                'message' => 'ไม่พบร้านนี้ หรือร้านปิดอยู่',
            ], 404);
        }

        ShopReport::firstOrCreate(
            ['shop_id' => $shop->id, 'user_id' => $user->id],
            ['reason' => $data['reason'], 'details' => $data['details'] ?? null]
        );

        return response()->json([
            'status' => true,
            'message' => 'ขอบคุณที่รายงาน ผู้ดูแลจะตรวจสอบร้านนี้',
        ]);
    }

    // =====================================================
    // HELPERS
    // =====================================================

    // สินค้าที่ผู้ใช้คนนี้เห็นในตลาด
    private function visibleProductsFor(User $user): Builder
    {
        $blockedIds = $user->blockedUsers()->pluck('users.id');

        return Product::query()
            ->visibleInMarket()
            ->whereHas('shop', fn ($shops) => $shops->whereNotIn('user_id', $blockedIds))
            ->whereDoesntHave('reports', fn ($reports) => $reports->where('user_id', $user->id));
    }

    // สินค้าที่เจ้าของร้านไม่ได้ซ่อน และไม่ถูกซ่อนโดย Admin
    private function onlyShown($query)
    {
        return $query->where('status', Product::STATUS_ACTIVE)->whereNull('hidden_at');
    }

    // ข้อมูลสินค้าแบบย่อสำหรับการ์ดในตาราง
    private function productCard(Product $product, bool $withShop = true): array
    {
        return [
            ...$product->only(['id', 'title', 'price', 'category', 'created_at']),
            'image_url' => $product->images->first()?->url,
            'images_count' => $product->images->count(),
            ...($withShop ? [
                'shop' => [
                    'id' => $product->shop->id,
                    'name' => $product->shop->name,
                    'province' => $product->shop->province,
                    'district' => $product->shop->district,
                    'logo_url' => $product->shop->logo_url,
                ],
            ] : []),
        ];
    }

    // ข้อมูลร้านที่เปิดให้ผู้ซื้อเห็น (ไม่มีข้อมูลเจ้าของบัญชี)
    private function shopPayload(Shop $shop): array
    {
        return $shop->only([
            'id',
            'name',
            'description',
            'category',
            'phone',
            'line_id',
            'province',
            'district',
            'logo_url',
            'is_featured',
        ]);
    }

    private function validateReport(Request $request): array
    {
        return $request->validate([
            'reason' => ['required', Rule::in(array_keys(config('market.report_reasons')))],
            'details' => 'nullable|string|max:1000',
        ]);
    }

    private function productNotFound()
    {
        return response()->json([
            'status' => false,
            'message' => 'ไม่พบสินค้านี้ หรือสินค้าถูกซ่อนแล้ว',
        ], 404);
    }

    private function cannotReportOwn()
    {
        return response()->json([
            'status' => false,
            'message' => 'ไม่สามารถรายงานร้านหรือสินค้าของตัวเองได้',
        ], 422);
    }
}
