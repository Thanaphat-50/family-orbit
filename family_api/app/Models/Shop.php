<?php

namespace App\Models;

use App\Services\MarketScreening;
use App\Support\MediaStorage;
use App\Support\PromptPay;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

class Shop extends Model
{
    public const STATUS_PENDING = 'pending';
    public const STATUS_ACTIVE = 'active';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_SUSPENDED = 'suspended';

    // เหตุผลที่ระบบปิดร้านเอง (ผู้ดูแลตรวจแล้วไม่ผิด → เปิดคืน)
    public const AUTO_SCREEN_REASON = 'ระบบพบคำที่อาจผิดกฎในชื่อหรือคำอธิบายร้าน ปิดไว้ชั่วคราวรอทีมงานตรวจสอบ';
    public const AUTO_REPORT_REASON = 'ร้านถูกรายงานจากผู้ใช้หลายคน ปิดไว้ชั่วคราวรอทีมงานตรวจสอบ';

    // ชื่อสถานะภาษาไทย (ใช้ในหน้า Admin และการแจ้งเตือน)
    public const STATUS_LABELS = [
        self::STATUS_PENDING => 'รออนุมัติ',
        self::STATUS_ACTIVE => 'เปิดขาย',
        self::STATUS_REJECTED => 'ไม่ผ่าน',
        self::STATUS_SUSPENDED => 'ถูกระงับ',
    ];

    protected $fillable = [
        'user_id',
        'name',
        'description',
        'category',
        'phone',
        'line_id',
        'province',
        'district',
        'opening_hours',
        'delivery_methods',
        'ship_within_days',
        'payment_methods',
        'promptpay_id',
        'bank_name',
        'bank_account_number',
        'bank_account_name',
        'logo_path',
        'video_path',
        'video_thumbnail_path',
        'status',
        'status_reason',
        'approved_at',
        'featured_until',
        'terms_accepted_at',
    ];

    // บัญชีรับเงินเห็นเฉพาะเจ้าของร้าน (MyShopController)
    // และผู้ซื้อตอนต้องโอน (Order::toPayload)
    protected $hidden = [
        'logo_path',
        'video_path',
        'video_thumbnail_path',
        'promptpay_id',
        'bank_name',
        'bank_account_number',
        'bank_account_name',
    ];

    protected $appends = [
        'logo_url',
        'is_featured',
        'video_url',
        'video_thumbnail_url',
    ];

    protected $casts = [
        'delivery_methods' => 'array',
        'payment_methods' => 'array',
        'ship_within_days' => 'integer',
        'approved_at' => 'datetime',
        'featured_until' => 'datetime',
        'terms_accepted_at' => 'datetime',
    ];

    public function owner()
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function products()
    {
        return $this->hasMany(Product::class);
    }

    public function images()
    {
        return $this->hasMany(ShopImage::class)->orderBy('sort')->orderBy('id');
    }

    public function reviews()
    {
        return $this->hasMany(ShopReview::class);
    }

    public function promotions()
    {
        return $this->hasMany(ShopPromotion::class);
    }

    public function orders()
    {
        return $this->hasMany(Order::class);
    }

    // =====================================================
    // สั่งซื้อในแอป
    // =====================================================

    // วิธีรับเงินที่ร้านเปิดและกรอกข้อมูลครบ
    public function readyPaymentMethods(): array
    {
        $methods = config('market.payment_methods');

        return collect($this->payment_methods ?? [])
            ->filter(fn ($key) => is_string($key) && array_key_exists($key, $methods))
            ->filter(fn (string $key) => match ($key) {
                'promptpay' => PromptPay::isValidId($this->promptpay_id),
                'bank' => filled($this->bank_name) && filled($this->bank_account_number),
                default => true,
            })
            ->unique()
            ->values()
            ->all();
    }

    // วิธีจ่ายที่ใช้กับวิธีรับสินค้านี้ได้ (เช่น เก็บเงินปลายทางใช้กับส่งพัสดุ)
    public function paymentMethodsFor(string $delivery): array
    {
        return array_values(array_filter(
            $this->readyPaymentMethods(),
            function (string $key) use ($delivery) {
                $allowed = config("market.payment_methods.{$key}.delivery");

                return $allowed === null || in_array($delivery, $allowed, true);
            }
        ));
    }

    // วิธีรับสินค้าที่สั่งในแอปได้ (มีวิธีจ่ายอย่างน้อย 1 แบบ)
    public function orderDeliveryMethods(): array
    {
        return array_values(array_filter(
            $this->delivery_methods ?? [],
            fn ($key) => is_string($key)
                && array_key_exists($key, config('market.delivery_methods'))
                && $this->paymentMethodsFor($key) !== []
        ));
    }

    // ข้อมูลจริงจากคำสั่งซื้อ: ขายแล้วกี่ชิ้น และส่งจริงเฉลี่ยกี่ชั่วโมงหลังชำระ
    // (ต้องมีอย่างน้อย 3 ออเดอร์ใน 90 วัน ไม่งั้นไม่แสดงค่าเฉลี่ย)
    public function salesStats(): array
    {
        $sold = (int) OrderItem::whereHas(
            'order',
            fn ($orders) => $orders->where('shop_id', $this->id)->where('status', Order::STATUS_COMPLETED)
        )->sum('quantity');

        $hours = Order::where('shop_id', $this->id)
            ->whereNotNull('shipped_at')
            ->where('shipped_at', '>=', now()->subDays(90))
            ->latest('shipped_at')
            ->limit(100)
            ->get(['created_at', 'paid_at', 'shipped_at'])
            ->map(fn (Order $order) => max(0, ($order->paid_at ?? $order->created_at)->diffInMinutes($order->shipped_at) / 60));

        return [
            'sold_count' => $sold,
            'avg_ship_hours' => $hours->count() >= 3 ? round($hours->avg(), 1) : null,
            'shipped_orders' => $hours->count(),
        ];
    }

    public function acceptsOrders(): bool
    {
        return $this->isActive() && $this->orderDeliveryMethods() !== [];
    }

    // ข้อมูลโอนเงินให้ผู้ซื้อ (null = ร้านเอาวิธีนี้ออกไปแล้ว)
    public function paymentInfo(string $method, float $amount): ?array
    {
        $accountName = filled($this->bank_account_name) ? $this->bank_account_name : $this->name;

        if ($method === 'promptpay' && PromptPay::isValidId($this->promptpay_id)) {
            return [
                'method' => 'promptpay',
                'promptpay_payload' => PromptPay::payload($this->promptpay_id, $amount),
                'promptpay_id' => PromptPay::maskedId($this->promptpay_id),
                'account_name' => $accountName,
            ];
        }

        if ($method === 'bank' && filled($this->bank_name) && filled($this->bank_account_number)) {
            return [
                'method' => 'bank',
                'bank_name' => $this->bank_name,
                'account_number' => $this->bank_account_number,
                'account_name' => $accountName,
            ];
        }

        return null;
    }

    // ข้อมูลบัญชีรับเงิน (เจ้าของร้านเท่านั้น)
    public function paymentSettings(): array
    {
        return [
            'payment_methods' => $this->payment_methods ?? [],
            'promptpay_id' => $this->promptpay_id,
            'bank_name' => $this->bank_name,
            'bank_account_number' => $this->bank_account_number,
            'bank_account_name' => $this->bank_account_name,
            'accepts_orders' => $this->acceptsOrders(),
        ];
    }

    public function getVideoUrlAttribute(): ?string
    {
        return MediaStorage::url($this->video_path);
    }

    public function getVideoThumbnailUrlAttribute(): ?string
    {
        return MediaStorage::url($this->video_thumbnail_path);
    }

    public function reports()
    {
        return $this->hasMany(ShopReport::class);
    }

    // ร้านที่แสดงในตลาด
    public function scopeActive(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_ACTIVE);
    }

    public function isActive(): bool
    {
        return $this->status === self::STATUS_ACTIVE;
    }

    // ร้านแนะนำที่ยังไม่หมดเวลา (ร้านต้องเปิดขายอยู่ด้วย)
    public function scopeFeatured(Builder $query): Builder
    {
        return $query->active()
            ->whereNotNull('featured_until')
            ->where('featured_until', '>', now());
    }

    public function isFeatured(): bool
    {
        return $this->isActive()
            && $this->featured_until !== null
            && $this->featured_until->isFuture();
    }

    public function getIsFeaturedAttribute(): bool
    {
        return $this->isFeatured();
    }

    // =====================================================
    // ร้านแนะนำ (ตั้งโดย Admin) + แจ้งเจ้าของร้าน
    // =====================================================

    public function feature(\DateTimeInterface $until): void
    {
        // แปลงเป็น UTC ก่อนบันทึก (Laravel บันทึกเวลาโดยไม่แปลงเขตเวลาให้)
        $this->featured_until = Carbon::instance($until)->utc();
        $this->save();

        $this->notifyOwner(
            'ร้านของคุณขึ้นร้านแนะนำแล้ว',
            'ร้าน "' . $this->name . '" แสดงด้านบนของตลาดถึงวันที่ '
                . $this->featured_until->copy()->setTimezone(config('market.timezone'))->format('d/m/Y')
        );
    }

    public function unfeature(): void
    {
        $this->featured_until = null;
        $this->save();
    }

    public function getLogoUrlAttribute(): ?string
    {
        return MediaStorage::url($this->logo_path);
    }

    // =====================================================
    // เปลี่ยนสถานะโดย Admin + แจ้งเจ้าของร้าน
    // =====================================================

    public function approve(): void
    {
        $this->status = self::STATUS_ACTIVE;
        $this->status_reason = null;
        $this->approved_at = $this->approved_at ?? now();
        $this->save();

        $this->notifyOwner(
            'ร้านของคุณเปิดขายแล้ว',
            'ร้าน "' . $this->name . '" ผ่านการตรวจสอบ เริ่มลงสินค้าได้เลย'
        );
    }

    public function reject(string $reason): void
    {
        $this->status = self::STATUS_REJECTED;
        $this->status_reason = $reason;
        $this->save();

        $this->notifyOwner(
            'ร้านยังไม่ผ่านการตรวจสอบ',
            'ร้าน "' . $this->name . '": ' . $reason
                . ' (แก้ไขข้อมูลแล้วส่งใหม่ได้)'
        );
    }

    public function suspend(string $reason): void
    {
        $this->status = self::STATUS_SUSPENDED;
        $this->status_reason = $reason;
        $this->save();

        $this->notifyOwner(
            'ร้านของคุณถูกระงับชั่วคราว',
            'ร้าน "' . $this->name . '": ' . $reason
        );
    }

    private function notifyOwner(string $title, string $message): void
    {
        AppNotification::create([
            'user_id' => $this->user_id,
            'family_id' => null,
            'type' => 'shop_status',
            'title' => $title,
            'message' => $message,
            'data' => [
                'shop_id' => $this->id,
                'status' => $this->status,
            ],
            'is_read' => false,
        ]);
    }

    // ลบไฟล์ทั้งหมดของร้านเมื่อร้านถูกลบด้วย $shop->delete()
    // (สินค้า รูป และสลิปถูกลบตาม cascade จึงต้องโหลด path ไว้ก่อน)
    protected static function booted(): void
    {
        // เปิดร้าน / แก้ชื่อหรือคำอธิบาย → ตรวจคำต้องห้าม (พบ → แจ้งผู้ดูแล)
        static::saved(function (Shop $shop) {
            if ($shop->wasRecentlyCreated || $shop->wasChanged(['name', 'description'])) {
                app(MarketScreening::class)->screenShop($shop);
            }
        });

        static::deleting(function (Shop $shop) {
            $shop->loadMissing(['images', 'promotions', 'orders', 'products.images', 'products.promotions']);
        });

        static::deleted(function (Shop $shop) {
            $paths = [
                $shop->logo_path,
                $shop->video_path,
                $shop->video_thumbnail_path,
                ...$shop->images->pluck('path')->all(),
                ...$shop->promotions->pluck('slip_path')->all(),
                ...$shop->orders->pluck('slip_path')->all(),
                ...$shop->products->flatMap(fn (Product $product) => $product->mediaPaths())->all(),
            ];

            DB::afterCommit(fn () => MediaStorage::delete($paths));
        });
    }

    // path ของไฟล์ทั้งหมดในร้านของผู้ใช้ (โลโก้ วิดีโอ รูปร้าน รูป/วิดีโอสินค้า สลิป)
    // ใช้ตอนลบบัญชี ซึ่งร้านถูกลบผ่าน cascade ของฐานข้อมูล
    public static function mediaPathsOfOwner(int $userId): array
    {
        $shops = self::where('user_id', $userId)->get(['id', 'logo_path', 'video_path', 'video_thumbnail_path']);

        $products = Product::whereIn('shop_id', $shops->pluck('id'))
            ->get(['id', 'video_path', 'video_thumbnail_path']);

        return [
            ...$shops->flatMap(fn (Shop $shop) => [$shop->logo_path, $shop->video_path, $shop->video_thumbnail_path])->all(),
            ...ShopImage::whereIn('shop_id', $shops->pluck('id'))->pluck('path')->all(),
            ...$products->flatMap(fn (Product $product) => [$product->video_path, $product->video_thumbnail_path])->all(),
            ...ProductImage::whereIn('product_id', $products->pluck('id'))->pluck('path')->all(),
            ...ProductPromotion::where('user_id', $userId)->pluck('slip_path')->all(),
            ...ShopPromotion::where('user_id', $userId)->pluck('slip_path')->all(),
            // สลิปคำสั่งซื้อ: ที่ผู้ใช้ซื้อ และที่ลูกค้าซื้อจากร้านของผู้ใช้
            ...Order::where('buyer_id', $userId)
                ->orWhereIn('shop_id', $shops->pluck('id'))
                ->pluck('slip_path')
                ->all(),
        ];
    }
}
