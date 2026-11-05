<?php

namespace App\Models;

use App\Support\MediaStorage;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

// =======================================================
// คำสั่งซื้อสินค้า (1 คำสั่งซื้อ = สินค้า 1 รายการ) ไม่ต้องรอร้านยืนยัน
//
// โอนพร้อมเพย์ / บัญชีธนาคาร:
//   awaiting_payment ─ผู้ซื้อแนบสลิป─▶ preparing (รอร้านจัดส่ง)
//   (ร้านเช็กแล้วเงินไม่เข้า → "สลิปไม่ถูกต้อง" กลับไป awaiting_payment)
// เก็บเงินปลายทาง / เงินสดตอนรับของ:
//   preparing ทันทีที่สั่ง
// preparing ─ร้านส่ง─▶ shipped ─ผู้ซื้อกดได้รับสินค้า (หรือครบกำหนด)─▶ completed
//
// ยกเลิกได้ก่อนร้านส่ง → cancelled (คืนสต็อก)
// สต็อกถูกจองตั้งแต่ตอนสั่ง จึงขายเกินจำนวนที่มีไม่ได้
// =======================================================

class Order extends Model
{
    public const STATUS_AWAITING_PAYMENT = 'awaiting_payment';
    public const STATUS_PREPARING = 'preparing';
    public const STATUS_SHIPPED = 'shipped';
    public const STATUS_COMPLETED = 'completed';
    public const STATUS_CANCELLED = 'cancelled';

    public const STATUS_LABELS = [
        self::STATUS_AWAITING_PAYMENT => 'รอชำระเงิน',
        self::STATUS_PREPARING => 'รอร้านจัดส่ง',
        self::STATUS_SHIPPED => 'ส่งสินค้าแล้ว',
        self::STATUS_COMPLETED => 'สำเร็จ',
        self::STATUS_CANCELLED => 'ยกเลิกแล้ว',
    ];

    // ยังไม่จบ
    public const OPEN_STATUSES = [
        self::STATUS_AWAITING_PAYMENT,
        self::STATUS_PREPARING,
        self::STATUS_SHIPPED,
    ];

    // ร้านต้องจัดส่ง (ตัวเลขบนปุ่มออเดอร์ของร้าน)
    public const SELLER_TODO_STATUSES = [
        self::STATUS_PREPARING,
    ];

    public const BY_BUYER = 'buyer';
    public const BY_SELLER = 'seller';
    public const BY_SYSTEM = 'system';

    protected $fillable = [
        'code',
        'buyer_id',
        'shop_id',
        'product_id',
        'product_title',
        'unit_price',
        'quantity',
        'shipping_fee',
        'total',
        'delivery_method',
        'payment_method',
        'recipient_name',
        'recipient_phone',
        'address',
        'note',
        'status',
        'payment_due_at',
        'slip_path',
        'slip_uploaded_at',
        'payment_note',
        'tracking_number',
        'seller_note',
        'cancel_reason',
        'cancelled_by',
        'paid_at',
        'shipped_at',
        'completed_at',
        'cancelled_at',
    ];

    protected $hidden = [
        'slip_path',
    ];

    protected $casts = [
        'unit_price' => 'decimal:2',
        'shipping_fee' => 'decimal:2',
        'total' => 'decimal:2',
        'quantity' => 'integer',
        'payment_due_at' => 'datetime',
        'slip_uploaded_at' => 'datetime',
        'paid_at' => 'datetime',
        'shipped_at' => 'datetime',
        'completed_at' => 'datetime',
        'cancelled_at' => 'datetime',
    ];

    public function buyer()
    {
        return $this->belongsTo(User::class, 'buyer_id');
    }

    public function shop()
    {
        return $this->belongsTo(Shop::class);
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function scopeOpen(Builder $query): Builder
    {
        return $query->whereIn('status', self::OPEN_STATUSES);
    }

    // ผู้ซื้อยังไม่ได้จ่าย (รอโอน / เก็บเงินปลายทาง / เงินสดที่ยังไม่ส่ง) ใช้จำกัดการสั่งค้างไว้
    public function scopeUnpaidReservation(Builder $query): Builder
    {
        $transfer = collect(config('market.payment_methods'))->filter(fn (array $method) => $method['transfer'])->keys();

        return $query->where(function (Builder $orders) use ($transfer) {
            $orders->where('status', self::STATUS_AWAITING_PAYMENT)
                ->orWhere(fn (Builder $cash) => $cash->where('status', self::STATUS_PREPARING)
                    ->whereNotIn('payment_method', $transfer));
        });
    }

    // =====================================================
    // สั่งซื้อ: จองสต็อกแล้วสร้างคำสั่งซื้อ (สต็อกไม่พอ → OutOfStock)
    // data ผ่านการตรวจใน OrderController แล้ว
    // =====================================================

    public static function place(User $buyer, Product $product, array $data): self
    {
        $quantity = (int) $data['quantity'];

        $shippingFee = in_array($data['delivery_method'], config('market.shipping_fee_methods'), true)
            ? (float) ($product->shipping_fee ?? 0)
            : 0.0;

        $transfer = (bool) config("market.payment_methods.{$data['payment_method']}.transfer", false);

        $order = DB::transaction(function () use ($buyer, $product, $data, $quantity, $shippingFee, $transfer) {
            // ลดสต็อกแบบมีเงื่อนไข (คนสั่งพร้อมกันก็ไม่ขายเกิน)
            $reserved = Product::whereKey($product->id)
                ->where('stock', '>=', $quantity)
                ->decrement('stock', $quantity);

            if ($reserved === 0) {
                throw new OutOfStock((int) Product::whereKey($product->id)->value('stock'));
            }

            $unitPrice = (float) $product->price;

            return self::create([
                'code' => self::newCode(),
                'buyer_id' => $buyer->id,
                'shop_id' => $product->shop_id,
                'product_id' => $product->id,
                'product_title' => $product->title,
                'unit_price' => $unitPrice,
                'quantity' => $quantity,
                'shipping_fee' => $shippingFee,
                'total' => round($unitPrice * $quantity + $shippingFee, 2),
                'delivery_method' => $data['delivery_method'],
                'payment_method' => $data['payment_method'],
                'recipient_name' => trim($data['recipient_name']),
                'recipient_phone' => preg_replace('/[\s\-]/', '', $data['recipient_phone']),
                'address' => filled($data['address'] ?? null) ? trim($data['address']) : null,
                'note' => filled($data['note'] ?? null) ? trim($data['note']) : null,
                // โอนเงิน → รอสลิป / เก็บเงินปลายทาง เงินสด → ร้านจัดส่งได้เลย
                'status' => $transfer ? self::STATUS_AWAITING_PAYMENT : self::STATUS_PREPARING,
                'payment_due_at' => $transfer ? now()->addHours(config('market.order_payment_hours')) : null,
            ]);
        });

        $order->notifySeller(
            'มีคำสั่งซื้อใหม่',
            "{$order->product_title} × {$order->quantity} · " . self::baht($order->total) . ' · '
                . ($transfer ? 'รอลูกค้าโอนเงิน' : $order->paymentLabel() . ' เตรียมจัดส่งได้เลย')
        );

        return $order;
    }

    // =====================================================
    // เปลี่ยนสถานะ (OrderController ตรวจสิทธิ์ด้วย actionsFor() ก่อนเรียก)
    // =====================================================

    // ผู้ซื้อแนบสลิป → รอร้านจัดส่งทันที
    public function attachSlip(UploadedFile $file): void
    {
        $path = $file->store('order_slips/' . $this->buyer_id, MediaStorage::disk())
            ?: throw new RuntimeException('Could not store the slip.');

        $old = $this->slip_path;

        $this->forceFill([
            'slip_path' => $path,
            'slip_uploaded_at' => now(),
            'paid_at' => now(),
            'payment_note' => null,
            'payment_due_at' => null,
            'status' => self::STATUS_PREPARING,
        ])->save();

        MediaStorage::delete([$old]);

        $this->notifySeller(
            'ลูกค้าโอนเงินแล้ว',
            "คำสั่งซื้อ {$this->code} · " . self::baht($this->total)
                . ' เช็กยอดเงินในบัญชี แล้วจัดส่งสินค้าได้เลย'
        );
    }

    // ร้านเช็กแล้วเงินไม่เข้า → ผู้ซื้อแนบสลิปใหม่ (นับเวลาชำระใหม่)
    public function rejectSlip(string $reason): void
    {
        $this->forceFill([
            'status' => self::STATUS_AWAITING_PAYMENT,
            'paid_at' => null,
            'payment_note' => $reason,
            'payment_due_at' => now()->addHours(config('market.order_payment_hours')),
        ])->save();

        $this->notifyBuyer('ร้านแจ้งว่าสลิปไม่ถูกต้อง', $reason . ' (แนบสลิปใหม่ได้ในคำสั่งซื้อ)');
    }

    public function ship(?string $trackingNumber, ?string $sellerNote): void
    {
        $this->forceFill([
            'status' => self::STATUS_SHIPPED,
            'shipped_at' => now(),
            'tracking_number' => $trackingNumber,
            'seller_note' => $sellerNote,
        ])->save();

        $this->notifyBuyer(
            $this->isHandover() ? 'ร้านส่งมอบสินค้าแล้ว' : 'ร้านส่งสินค้าแล้ว',
            '"' . $this->product_title . '"'
                . ($trackingNumber ? " · เลขพัสดุ {$trackingNumber}" : '')
                . ' ได้รับแล้วกด "ได้รับสินค้าแล้ว" ในคำสั่งซื้อ'
        );
    }

    // ผู้ซื้อได้รับสินค้า (by = system เมื่อครบกำหนดแล้วผู้ซื้อไม่ได้กด)
    public function complete(string $by = self::BY_BUYER): void
    {
        $this->forceFill([
            'status' => self::STATUS_COMPLETED,
            'completed_at' => now(),
            // เก็บเงินปลายทาง / เงินสด: จ่ายตอนรับของ
            'paid_at' => $this->paid_at ?? now(),
        ])->save();

        $this->notifySeller(
            'คำสั่งซื้อสำเร็จ',
            $by === self::BY_SYSTEM
                ? "คำสั่งซื้อ {$this->code} ครบกำหนดยืนยันรับสินค้าแล้ว"
                : "ลูกค้าได้รับ \"{$this->product_title}\" แล้ว"
        );
    }

    // ยกเลิก + คืนสต็อก แล้วแจ้งอีกฝ่าย
    public function cancel(string $by, ?string $reason): void
    {
        $paid = $this->paid_at !== null;

        DB::transaction(function () use ($by, $reason) {
            $this->forceFill([
                'status' => self::STATUS_CANCELLED,
                'cancelled_at' => now(),
                'cancelled_by' => $by,
                'cancel_reason' => $reason,
                'payment_due_at' => null,
            ])->save();

            if ($this->product_id !== null) {
                Product::whereKey($this->product_id)->increment('stock', $this->quantity);
            }
        });

        $message = "คำสั่งซื้อ {$this->code} \"{$this->product_title}\"" . ($reason ? " · {$reason}" : '');

        if ($by !== self::BY_BUYER) {
            $this->notifyBuyer(
                'คำสั่งซื้อถูกยกเลิก',
                $message . ($paid ? ' · ร้านต้องคืนเงินที่คุณโอนให้' : '')
            );
        }

        if ($by !== self::BY_SELLER) {
            $this->notifySeller(
                'คำสั่งซื้อถูกยกเลิก',
                $message . ($paid ? ' · ลูกค้าโอนเงินแล้ว กรุณาคืนเงินให้ลูกค้า' : '')
            );
        }
    }

    // =====================================================
    // ครบกำหนดเวลา (เรียกก่อนแสดงรายการ ไม่ต้องตั้งเวลาบนเซิร์ฟเวอร์)
    // =====================================================

    public static function expireStale(): void
    {
        $now = now();

        self::where('status', self::STATUS_AWAITING_PAYMENT)
            ->where('payment_due_at', '<', $now)
            ->get()
            ->each(fn (Order $order) => $order->cancel(self::BY_SYSTEM, 'ไม่ได้แนบสลิปภายในเวลาที่กำหนด'));

        self::where('status', self::STATUS_SHIPPED)
            ->where('shipped_at', '<', $now->copy()->subDays(config('market.order_auto_complete_days')))
            ->get()
            ->each(fn (Order $order) => $order->complete(self::BY_SYSTEM));
    }

    // =====================================================
    // สิทธิ์และข้อมูลที่ส่งให้แอป
    // =====================================================

    public function isBuyer(User $user): bool
    {
        return (int) $this->buyer_id === (int) $user->id;
    }

    public function isSeller(User $user): bool
    {
        return (int) $this->shop?->user_id === (int) $user->id;
    }

    // โอนเงินก่อนส่ง (ต้องแนบสลิป)
    public function isTransfer(): bool
    {
        return (bool) config("market.payment_methods.{$this->payment_method}.transfer", false);
    }

    // รับที่ร้าน / นัดรับ (ร้านส่งมอบเอง ไม่มีเลขพัสดุ)
    public function isHandover(): bool
    {
        return !in_array($this->delivery_method, config('market.address_methods'), true);
    }

    // ร้านควรส่งภายในวันนี้ (เกินแล้วผู้ซื้อยกเลิกได้แม้โอนเงินแล้ว)
    public function shipDeadline(): ?Carbon
    {
        if ($this->status !== self::STATUS_PREPARING) {
            return null;
        }

        return ($this->paid_at ?? $this->created_at)?->copy()->addDays(config('market.order_ship_days'));
    }

    public function isShipOverdue(): bool
    {
        return $this->shipDeadline()?->isPast() ?? false;
    }

    // ปุ่มที่ผู้ใช้คนนี้กดได้ตอนนี้
    public function actionsFor(User $user): array
    {
        if ($this->isBuyer($user)) {
            return match ($this->status) {
                self::STATUS_AWAITING_PAYMENT => ['pay', 'cancel'],
                // ยังไม่ได้จ่าย ยกเลิกได้ / โอนแล้ว ยกเลิกได้เมื่อร้านส่งช้าเกินกำหนด
                self::STATUS_PREPARING => !$this->isTransfer() || $this->isShipOverdue() ? ['cancel'] : [],
                self::STATUS_SHIPPED => ['received'],
                default => [],
            };
        }

        if ($this->isSeller($user)) {
            return match ($this->status) {
                self::STATUS_AWAITING_PAYMENT => ['cancel'],
                self::STATUS_PREPARING => $this->isTransfer() && $this->slip_path !== null
                    ? ['ship', 'reject_slip', 'cancel']
                    : ['ship', 'cancel'],
                default => [],
            };
        }

        return [];
    }

    public function statusLabel(): string
    {
        if ($this->status === self::STATUS_SHIPPED && $this->isHandover()) {
            return 'ส่งมอบสินค้าแล้ว';
        }

        return self::STATUS_LABELS[$this->status] ?? $this->status;
    }

    public function paymentLabel(): string
    {
        return config("market.payment_methods.{$this->payment_method}.label", $this->payment_method);
    }

    public function getSlipUrlAttribute(): ?string
    {
        return MediaStorage::url($this->slip_path);
    }

    public function toPayload(User $viewer): array
    {
        $this->loadMissing(['shop', 'buyer', 'product.images']);

        $isBuyer = $this->isBuyer($viewer);

        // ข้อมูลโอนเงินของร้าน เห็นเฉพาะผู้ซื้อตอนต้องโอน
        $payment = $isBuyer && $this->isTransfer() && $this->status === self::STATUS_AWAITING_PAYMENT
            ? $this->shop?->paymentInfo($this->payment_method, (float) $this->total)
            : null;

        return [
            ...$this->only([
                'id', 'code', 'status', 'product_id', 'product_title',
                'unit_price', 'quantity', 'shipping_fee', 'total',
                'delivery_method', 'payment_method',
                'recipient_name', 'recipient_phone', 'address', 'note',
                'payment_note', 'tracking_number', 'seller_note',
                'cancel_reason', 'cancelled_by',
                'created_at', 'slip_uploaded_at', 'paid_at',
                'shipped_at', 'completed_at', 'cancelled_at',
            ]),
            'role' => $isBuyer ? self::BY_BUYER : self::BY_SELLER,
            'status_label' => $this->statusLabel(),
            'delivery_label' => config("market.delivery_methods.{$this->delivery_method}", $this->delivery_method),
            'payment_label' => $this->paymentLabel(),
            'is_transfer' => $this->isTransfer(),
            'is_handover' => $this->isHandover(),
            'image_url' => $this->product?->images->first()?->url,
            'slip_url' => $this->slip_url,
            'payment_deadline' => $this->status === self::STATUS_AWAITING_PAYMENT ? $this->payment_due_at : null,
            'ship_deadline' => $this->shipDeadline(),
            'auto_complete_at' => $this->status === self::STATUS_SHIPPED
                ? $this->shipped_at?->copy()->addDays(config('market.order_auto_complete_days'))
                : null,
            'actions' => $this->actionsFor($viewer),
            'shop' => $this->shop ? [
                ...$this->shop->only(['id', 'name', 'phone', 'line_id']),
                'logo_url' => $this->shop->logo_url,
            ] : null,
            'buyer' => !$isBuyer && $this->buyer ? [
                'id' => $this->buyer->id,
                'name' => $this->buyer->name,
                'profile_photo_url' => $this->buyer->profile_photo_url,
            ] : null,
            'payment' => $payment,
        ];
    }

    // =====================================================
    // HELPERS
    // =====================================================

    // OR + ปีเดือนวัน + ตัวอักษรสุ่ม เช่น OR261105K7Q2MZ
    private static function newCode(): string
    {
        do {
            $code = 'OR' . now(config('market.timezone'))->format('ymd') . strtoupper(Str::random(6));
        } while (self::where('code', $code)->exists());

        return $code;
    }

    public static function baht(mixed $amount): string
    {
        $value = (float) $amount;

        return '฿' . number_format($value, fmod($value, 1.0) === 0.0 ? 0 : 2);
    }

    private function notifyBuyer(string $title, string $message): void
    {
        $this->notify($this->buyer_id, self::BY_BUYER, $title, $message);
    }

    private function notifySeller(string $title, string $message): void
    {
        $sellerId = $this->shop?->user_id ?? Shop::whereKey($this->shop_id)->value('user_id');

        if ($sellerId) {
            $this->notify((int) $sellerId, self::BY_SELLER, $title, $message);
        }
    }

    private function notify(int $userId, string $role, string $title, string $message): void
    {
        AppNotification::create([
            'user_id' => $userId,
            'family_id' => null,
            'type' => 'order_status',
            'title' => $title,
            'message' => $message,
            'data' => [
                'order_id' => $this->id,
                'role' => $role,
            ],
            'is_read' => false,
        ]);
    }

    protected static function booted(): void
    {
        static::deleted(function (Order $order) {
            $path = $order->slip_path;

            DB::afterCommit(fn () => MediaStorage::delete([$path]));
        });
    }
}
