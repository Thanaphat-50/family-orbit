<?php

namespace App\Models;

use App\Services\SlipVerifier;
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
    // ตรวจสลิปอัตโนมัติไม่ได้ → ร้านตรวจยอดเงินเอง
    public const STATUS_PAYMENT_REVIEW = 'payment_review';
    public const STATUS_PREPARING = 'preparing';
    public const STATUS_SHIPPED = 'shipped';
    public const STATUS_COMPLETED = 'completed';
    public const STATUS_CANCELLED = 'cancelled';

    public const STATUS_LABELS = [
        self::STATUS_AWAITING_PAYMENT => 'รอชำระเงิน',
        self::STATUS_PAYMENT_REVIEW => 'รอตรวจสอบการชำระเงิน',
        self::STATUS_PREPARING => 'รอร้านจัดส่ง',
        self::STATUS_SHIPPED => 'ส่งสินค้าแล้ว',
        self::STATUS_COMPLETED => 'สำเร็จ',
        self::STATUS_CANCELLED => 'ยกเลิกแล้ว',
    ];

    // ยังไม่จบ
    public const OPEN_STATUSES = [
        self::STATUS_AWAITING_PAYMENT,
        self::STATUS_PAYMENT_REVIEW,
        self::STATUS_PREPARING,
        self::STATUS_SHIPPED,
    ];

    // ร้านต้องจัดส่ง (ตัวเลขบนปุ่มออเดอร์ของร้าน)
    public const SELLER_TODO_STATUSES = [
        self::STATUS_PAYMENT_REVIEW,
        self::STATUS_PREPARING,
    ];

    public const BY_BUYER = 'buyer';
    public const BY_SELLER = 'seller';
    public const BY_SYSTEM = 'system';

    protected $fillable = [
        'code',
        'checkout_id',
        'buyer_id',
        'shop_id',
        'product_id',
        'product_title',
        'unit_price',
        'quantity',
        'items_total',
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
        'items_total' => 'decimal:2',
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

    public function items()
    {
        return $this->hasMany(OrderItem::class)->orderBy('id');
    }

    public function payments()
    {
        return $this->hasMany(PaymentTransaction::class)->orderBy('id');
    }

    public function histories()
    {
        return $this->hasMany(OrderStatusHistory::class)->orderBy('id');
    }

    // =====================================================
    // สั่งซื้อ (1 ร้าน หลายรายการ): จองสต็อกแล้วสร้างคำสั่งซื้อ
    // lines = [['product' => Product, 'variant' => ?ProductVariant, 'quantity' => int, 'unit_price' => float]]
    // ราคามาจาก OrderController ที่อ่านจากฐานข้อมูล (ไม่เชื่อราคาจากแอป)
    // สต็อกไม่พอ → OutOfStock (เรียกใน DB::transaction ของ Controller → ยกเลิกทั้งหมด)
    // =====================================================

    public static function placeGroup(User $buyer, Shop $shop, array $lines, array $data, ?string $checkoutId = null): self
    {
        foreach ($lines as $line) {
            self::reserveStock($line['product'], $line['variant'], (int) $line['quantity']);
        }

        [$itemsTotal, $shippingFee] = self::totalsFor($lines, $data['delivery_method']);

        $transfer = (bool) config("market.payment_methods.{$data['payment_method']}.transfer", false);

        $first = $lines[0];

        $order = self::create([
            'code' => self::newCode(),
            'checkout_id' => $checkoutId,
            'buyer_id' => $buyer->id,
            'shop_id' => $shop->id,
            // สรุปไว้ที่คำสั่งซื้อ (แอปเวอร์ชันเก่าแสดงจากช่องนี้) รายการจริงอยู่ใน order_items
            'product_id' => $first['product']->id,
            'product_title' => Str::limit(
                $first['product']->title . (count($lines) > 1 ? ' และอีก ' . (count($lines) - 1) . ' รายการ' : ''),
                117
            ),
            'unit_price' => $first['unit_price'],
            'quantity' => array_sum(array_map(fn (array $line) => (int) $line['quantity'], $lines)),
            'items_total' => $itemsTotal,
            'shipping_fee' => $shippingFee,
            'total' => round($itemsTotal + $shippingFee, 2),
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

        foreach ($lines as $line) {
            $order->items()->create([
                'product_id' => $line['product']->id,
                'variant_id' => $line['variant']?->id,
                'title' => $line['product']->title,
                'variant_name' => $line['variant']?->name,
                'unit_price' => $line['unit_price'],
                'quantity' => (int) $line['quantity'],
                'subtotal' => round($line['unit_price'] * $line['quantity'], 2),
            ]);
        }

        $order->recordStatus(self::BY_BUYER, 'สั่งซื้อ');

        return $order;
    }

    // [ยอดสินค้า, ค่าส่ง] ของคำสั่งซื้อ 1 ร้าน (ใช้ทั้งตอนแสดงหน้าสั่งซื้อและตอนบันทึก)
    // ค่าส่งคิดครั้งเดียวต่อคำสั่งซื้อ: ใช้ค่าส่งสูงสุดของสินค้าในคำสั่งซื้อ
    public static function totalsFor(array $lines, string $deliveryMethod): array
    {
        $itemsTotal = round(array_sum(array_map(
            fn (array $line) => (float) $line['unit_price'] * (int) $line['quantity'],
            $lines
        )), 2);

        $shippingFee = in_array($deliveryMethod, config('market.shipping_fee_methods'), true) && $lines !== []
            ? (float) max(array_map(fn (array $line) => (float) ($line['product']->shipping_fee ?? 0), $lines))
            : 0.0;

        return [$itemsTotal, $shippingFee];
    }

    // แจ้งร้านว่ามีคำสั่งซื้อใหม่ (เรียกหลังบันทึกคำสั่งซื้อทั้งหมดสำเร็จ)
    public function announceToSeller(): void
    {
        $this->notifySeller(
            'มีคำสั่งซื้อใหม่',
            "{$this->product_title} · {$this->quantity} ชิ้น · " . self::baht($this->total) . ' · '
                . ($this->isTransfer() ? 'รอลูกค้าโอนเงิน' : $this->paymentLabel() . ' เตรียมจัดส่งได้เลย')
        );
    }

    // ลดสต็อกแบบมีเงื่อนไข (คนสั่งพร้อมกันก็ไม่ขายเกิน)
    private static function reserveStock(Product $product, ?ProductVariant $variant, int $quantity): void
    {
        if ($variant) {
            $reserved = ProductVariant::whereKey($variant->id)
                ->where('stock', '>=', $quantity)
                ->decrement('stock', $quantity);

            if ($reserved === 0) {
                throw new OutOfStock(
                    (int) ProductVariant::whereKey($variant->id)->value('stock'),
                    "{$product->title} ({$variant->name})"
                );
            }

            // สต็อกรวมของสินค้า = ผลรวมของตัวเลือก
            Product::whereKey($product->id)->where('stock', '>=', $quantity)->decrement('stock', $quantity);

            return;
        }

        $reserved = Product::whereKey($product->id)
            ->where('stock', '>=', $quantity)
            ->decrement('stock', $quantity);

        if ($reserved === 0) {
            throw new OutOfStock((int) Product::whereKey($product->id)->value('stock'), $product->title);
        }
    }

    // คืนสต็อกเมื่อยกเลิก
    private function restoreStock(): void
    {
        foreach ($this->items()->get() as $item) {
            if ($item->variant_id !== null) {
                ProductVariant::whereKey($item->variant_id)->increment('stock', $item->quantity);
            }

            if ($item->product_id !== null) {
                Product::whereKey($item->product_id)->increment('stock', $item->quantity);
            }
        }
    }

    public function recordStatus(string $actor, ?string $note = null): void
    {
        $this->histories()->create([
            'status' => $this->status,
            'actor' => $actor,
            'note' => $note === null ? null : Str::limit($note, 297),
        ]);
    }

    // =====================================================
    // เปลี่ยนสถานะ (OrderController ตรวจสิทธิ์ด้วย actionsFor() ก่อนเรียก)
    // =====================================================

    // ผู้ซื้อแนบสลิป → รอร้านจัดส่งทันที
    // ผู้ซื้อแนบสลิป → ตรวจสลิป (App\Services\SlipVerifier)
    // ผ่าน = ชำระแล้ว (รอร้านจัดส่ง) / ไม่ผ่าน = แนบใหม่ / ตรวจไม่ได้ = ร้านตรวจยอดเอง
    public function attachSlip(UploadedFile $file): PaymentTransaction
    {
        $check = app(SlipVerifier::class)->check(
            (string) file_get_contents($file->getRealPath()),
            $file->getClientOriginalName() ?: 'slip.jpg',
            $this
        );

        $payment = $this->payments()->create([
            ...$check,
            'method' => $this->payment_method,
            'amount' => $this->total,
            'verified_at' => $check['status'] === PaymentTransaction::STATUS_VERIFIED ? now() : null,
        ]);

        // สลิปไม่ผ่าน → ไม่เก็บรูป ให้แนบใหม่
        if ($payment->status === PaymentTransaction::STATUS_REJECTED) {
            $this->forceFill(['payment_note' => $payment->reason])->save();

            $this->recordStatus(self::BY_SYSTEM, 'สลิปไม่ผ่าน: ' . $payment->reason);

            return $payment;
        }

        $path = $file->store('order_slips/' . $this->buyer_id, MediaStorage::disk())
            ?: throw new RuntimeException('Could not store the slip.');

        $old = $this->slip_path;

        $verified = $payment->status === PaymentTransaction::STATUS_VERIFIED;

        $this->forceFill([
            'slip_path' => $path,
            'slip_uploaded_at' => now(),
            'paid_at' => $verified ? now() : null,
            'payment_note' => null,
            'payment_due_at' => null,
            'status' => $verified ? self::STATUS_PREPARING : self::STATUS_PAYMENT_REVIEW,
        ])->save();

        MediaStorage::delete([$old]);

        if ($verified) {
            $this->recordStatus(self::BY_SYSTEM, 'ระบบตรวจสลิปแล้ว ชำระเงินสำเร็จ');

            $this->notifySeller(
                'ลูกค้าชำระเงินแล้ว',
                "คำสั่งซื้อ {$this->code} · " . self::baht($this->total) . ' ระบบตรวจสลิปแล้ว จัดส่งสินค้าได้เลย'
            );
        } else {
            $this->recordStatus(self::BY_BUYER, 'แนบสลิป · ' . $payment->reason);

            $this->notifySeller(
                'ลูกค้าแนบสลิปแล้ว',
                "คำสั่งซื้อ {$this->code} · " . self::baht($this->total)
                    . ' กรุณาเช็กยอดเงินในบัญชีแล้วกดยืนยันรับเงิน'
            );
        }

        return $payment;
    }

    // ร้านเช็กยอดในบัญชีแล้ว (ตอนตรวจสลิปอัตโนมัติไม่ได้)
    public function confirmPayment(): void
    {
        $this->payments()->where('status', PaymentTransaction::STATUS_REVIEW)->update([
            'status' => PaymentTransaction::STATUS_CONFIRMED,
            'reason' => null,
            'verified_at' => now(),
        ]);

        $this->forceFill([
            'status' => self::STATUS_PREPARING,
            'paid_at' => now(),
        ])->save();

        $this->recordStatus(self::BY_SELLER, 'ร้านยืนยันว่าได้รับเงินแล้ว');

        $this->notifyBuyer('ร้านได้รับเงินแล้ว', "คำสั่งซื้อ {$this->code} รอร้านจัดส่งสินค้า");
    }

    // ร้านเช็กแล้วเงินไม่เข้า → ผู้ซื้อแนบสลิปใหม่ (นับเวลาชำระใหม่)
    public function rejectSlip(string $reason): void
    {
        $this->payments()->where('status', PaymentTransaction::STATUS_REVIEW)->update([
            'status' => PaymentTransaction::STATUS_REJECTED,
            'reason' => $reason,
        ]);

        $this->forceFill([
            'status' => self::STATUS_AWAITING_PAYMENT,
            'paid_at' => null,
            'payment_note' => $reason,
            'payment_due_at' => now()->addHours(config('market.order_payment_hours')),
        ])->save();

        $this->recordStatus(self::BY_SELLER, 'สลิปไม่ถูกต้อง: ' . $reason);

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

        $this->recordStatus(self::BY_SELLER, $trackingNumber ? "เลขพัสดุ {$trackingNumber}" : null);

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

        $this->recordStatus($by, $by === self::BY_SYSTEM ? 'ครบกำหนด ระบบยืนยันรับสินค้าให้' : 'ได้รับสินค้าแล้ว');

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

            $this->restoreStock();

            $this->recordStatus($by, $reason);
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
                self::STATUS_PAYMENT_REVIEW => ['confirm_payment', 'reject_slip', 'cancel'],
                self::STATUS_PREPARING => ['ship', 'cancel'],
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
        $this->loadMissing(['shop', 'buyer', 'product.images', 'items.product.images', 'histories', 'payments']);

        $isBuyer = $this->isBuyer($viewer);

        // ข้อมูลโอนเงินของร้าน เห็นเฉพาะผู้ซื้อตอนต้องโอน
        $payment = $isBuyer && $this->isTransfer() && $this->status === self::STATUS_AWAITING_PAYMENT
            ? $this->shop?->paymentInfo($this->payment_method, (float) $this->total)
            : null;

        return [
            ...$this->only([
                'id', 'code', 'status', 'product_id', 'product_title',
                'unit_price', 'quantity', 'items_total', 'shipping_fee', 'total',
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
            'image_url' => $this->items->first()?->product?->images->first()?->url
                ?? $this->product?->images->first()?->url,
            'items' => $this->items->map(fn (OrderItem $item) => $item->toPayload())->values(),
            // ประวัติการชำระเงิน (ทุกครั้งที่แนบสลิป) ใหม่สุดอยู่บน
            'payments' => $this->payments->reverse()->map(fn (PaymentTransaction $payment) => $payment->toPayload())->values(),
            'slip_check' => app(SlipVerifier::class)->enabled(),
            // ประวัติสถานะ ใหม่สุดอยู่บน
            'history' => $this->histories->reverse()->map(fn (OrderStatusHistory $history) => [
                'status' => $history->status,
                'status_label' => self::STATUS_LABELS[$history->status] ?? $history->status,
                'actor' => $history->actor,
                'note' => $history->note,
                'created_at' => $history->created_at,
            ])->values(),
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
