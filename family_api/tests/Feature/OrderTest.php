<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Order;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

// สั่งซื้อสินค้าในแอป: ผู้ซื้อสั่ง → ร้านรับ → โอน + สลิป → ร้านยืนยัน → ส่ง → ได้รับสินค้า
class OrderTest extends TestCase
{
    use FakesImages, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());
    }

    private function seller(array $shop = []): array
    {
        $owner = User::factory()->create();

        $shop = Shop::create([
            'user_id' => $owner->id,
            'name' => 'ร้าน ' . $owner->id,
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => Shop::STATUS_ACTIVE,
            'terms_accepted_at' => now(),
            'delivery_methods' => ['shipping', 'storefront'],
            'payment_methods' => ['promptpay', 'bank', 'cod', 'cash'],
            'promptpay_id' => '0899999999',
            'bank_name' => 'ธนาคารกสิกรไทย',
            'bank_account_number' => '1234567890',
            'bank_account_name' => 'ร้านทดสอบ',
            ...$shop,
        ]);

        return [$owner, $shop];
    }

    private function product(Shop $shop, array $fields = []): Product
    {
        return $shop->products()->create([
            'title' => 'มะม่วงน้ำดอกไม้',
            'price' => 100,
            'stock' => 5,
            'shipping_fee' => 40,
            'category' => 'produce',
            'status' => Product::STATUS_ACTIVE,
            ...$fields,
        ]);
    }

    private function orderData(Product $product, array $fields = []): array
    {
        return [
            'product_id' => $product->id,
            'quantity' => 2,
            'delivery_method' => 'shipping',
            'payment_method' => 'promptpay',
            'recipient_name' => 'คุณแม่',
            'recipient_phone' => '081-111-2222',
            'address' => '99 ถ.นิมมาน เชียงใหม่ 50200',
            ...$fields,
        ];
    }

    private function placeOrder(User $buyer, Product $product, array $fields = []): Order
    {
        Sanctum::actingAs($buyer);

        $id = $this->postJson('/api/orders', $this->orderData($product, $fields))
            ->assertCreated()
            ->json('order.id');

        return Order::findOrFail($id);
    }

    public function test_transfer_order_full_flow(): void
    {
        [$seller, $shop] = $this->seller();
        $product = $this->product($shop);
        $buyer = User::factory()->create();

        Sanctum::actingAs($buyer);

        $checkout = $this->getJson("/api/orders/checkout?product_id={$product->id}")
            ->assertOk()
            ->assertJsonPath('max_quantity', 5)
            ->json('delivery_methods');

        $shipping = collect($checkout)->firstWhere('key', 'shipping');
        $this->assertEquals(40, $shipping['shipping_fee']);
        $this->assertTrue($shipping['needs_address']);
        $this->assertEqualsCanonicalizing(['promptpay', 'bank', 'cod'], collect($shipping['payment_methods'])->pluck('key')->all());
        $this->assertEqualsCanonicalizing(
            ['promptpay', 'bank', 'cash'],
            collect(collect($checkout)->firstWhere('key', 'storefront')['payment_methods'])->pluck('key')->all()
        );

        // สั่งแล้วโอนได้เลย ไม่ต้องรอร้านยืนยัน
        $response = $this->postJson('/api/orders', $this->orderData($product))
            ->assertCreated()
            ->assertJsonPath('order.status', Order::STATUS_AWAITING_PAYMENT)
            ->assertJsonPath('order.total', '240.00')
            ->assertJsonPath('order.actions', ['pay', 'cancel']);

        $id = $response->json('order.id');
        $payment = $response->json('order.payment');

        $this->assertSame('promptpay', $payment['method']);
        $this->assertStringContainsString('5406240.00', $payment['promptpay_payload']);
        $this->assertStringNotContainsString('0899999999', json_encode($payment));
        $this->assertNotNull($response->json('order.payment_deadline'));

        // จองสต็อกทันที
        $this->assertSame(3, $product->refresh()->stock);
        $this->assertTrue(AppNotification::where('user_id', $seller->id)->where('type', 'order_status')->exists());

        // ร้านยังไม่ต้องทำอะไร (รอลูกค้าโอน) และไม่เห็นข้อมูลโอนของตัวเอง
        Sanctum::actingAs($seller);

        $this->getJson('/api/my-shop/orders?filter=open')
            ->assertOk()
            ->assertJsonPath('todo', 0)
            ->assertJsonPath('orders.0.buyer.id', $buyer->id)
            ->assertJsonPath('orders.0.actions', ['cancel'])
            ->assertJsonPath('orders.0.payment', null);

        // แนบสลิป → รอร้านจัดส่งทันที
        Sanctum::actingAs($buyer);

        $this->post("/api/orders/{$id}/slip", ['slip' => $this->fakePng('slip.png')], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('order.status', Order::STATUS_PREPARING)
            ->assertJsonPath('order.status_label', 'รอร้านจัดส่ง')
            ->assertJsonPath('order.actions', [])
            ->assertJsonPath('order.payment', null);

        // ร้านส่งสินค้า
        Sanctum::actingAs($seller);

        $this->getJson('/api/my-shop/orders?filter=todo')
            ->assertJsonPath('todo', 1)
            ->assertJsonPath('orders.0.actions', ['ship', 'reject_slip', 'cancel']);

        $this->postJson("/api/orders/{$id}/ship", ['tracking_number' => 'TH123456789'])
            ->assertOk()
            ->assertJsonPath('order.status', Order::STATUS_SHIPPED)
            ->assertJsonPath('order.tracking_number', 'TH123456789');

        // ผู้ซื้อได้รับสินค้า
        Sanctum::actingAs($buyer);

        $this->postJson("/api/orders/{$id}/received")
            ->assertOk()
            ->assertJsonPath('order.status', Order::STATUS_COMPLETED);

        $this->getJson('/api/orders?filter=completed')
            ->assertOk()
            ->assertJsonCount(1, 'orders');

        // ร้านส่งแล้ว
        $this->assertSame(1, AppNotification::where('user_id', $buyer->id)->where('type', 'order_status')->count());
    }

    public function test_seller_can_send_a_bad_slip_back(): void
    {
        [$seller, $shop] = $this->seller();
        $product = $this->product($shop);
        $buyer = User::factory()->create();

        $order = $this->placeOrder($buyer, $product);
        $order->attachSlip($this->fakePng('slip.png'));

        Sanctum::actingAs($seller);

        $this->postJson("/api/orders/{$order->id}/reject-slip")->assertJsonValidationErrors('reason');

        $this->postJson("/api/orders/{$order->id}/reject-slip", ['reason' => 'ยังไม่มีเงินเข้า'])
            ->assertOk()
            ->assertJsonPath('order.status', Order::STATUS_AWAITING_PAYMENT)
            ->assertJsonPath('order.payment_note', 'ยังไม่มีเงินเข้า')
            ->assertJsonPath('order.paid_at', null);

        // ผู้ซื้อเห็น QR อีกครั้ง แนบใหม่ได้
        Sanctum::actingAs($buyer);

        $this->getJson("/api/orders/{$order->id}")
            ->assertJsonPath('order.actions', ['pay', 'cancel'])
            ->assertJsonPath('order.payment.method', 'promptpay');
    }

    public function test_cash_and_cod_go_straight_to_shipping(): void
    {
        [$seller, $shop] = $this->seller();
        $product = $this->product($shop);
        $buyer = User::factory()->create();

        $pickup = $this->placeOrder($buyer, $product, [
            'delivery_method' => 'storefront',
            'payment_method' => 'cash',
            'address' => null,
            'quantity' => 1,
        ]);

        $this->assertSame(Order::STATUS_PREPARING, $pickup->status);
        $this->assertEquals(100, $pickup->total);
        $this->assertEquals(0, $pickup->shipping_fee);

        $cod = $this->placeOrder($buyer, $product, ['payment_method' => 'cod', 'quantity' => 1]);

        $this->assertSame(Order::STATUS_PREPARING, $cod->status);
        $this->assertEquals(140, $cod->total);

        // ยังไม่ได้จ่าย → ผู้ซื้อยกเลิกได้ก่อนร้านส่ง
        Sanctum::actingAs($buyer);
        $this->getJson("/api/orders/{$cod->id}")->assertJsonPath('order.actions', ['cancel']);

        Sanctum::actingAs($seller);

        $this->getJson("/api/orders/{$pickup->id}")->assertJsonPath('order.actions', ['ship', 'cancel']);

        $this->postJson("/api/orders/{$pickup->id}/ship")
            ->assertOk()
            ->assertJsonPath('order.status_label', 'ส่งมอบสินค้าแล้ว');

        Sanctum::actingAs($buyer);

        $this->postJson("/api/orders/{$pickup->id}/received")->assertOk();
        $this->assertNotNull($pickup->refresh()->paid_at);
    }

    public function test_stock_cannot_be_oversold_and_cancel_restores_it(): void
    {
        [, $shop] = $this->seller();
        $product = $this->product($shop, ['stock' => 1]);

        $first = $this->placeOrder(User::factory()->create(), $product, ['quantity' => 1]);

        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/orders', $this->orderData($product, ['quantity' => 1]))
            ->assertUnprocessable()
            ->assertJsonPath('message', 'สินค้าหมดแล้ว');

        $this->assertSame(0, $product->refresh()->stock);

        Sanctum::actingAs($first->buyer);

        $this->postJson("/api/orders/{$first->id}/cancel")
            ->assertOk()
            ->assertJsonPath('order.status', Order::STATUS_CANCELLED);

        $this->assertSame(1, $product->refresh()->stock);

        // ขอเกินจำนวนที่เหลือ
        $this->postJson('/api/orders', $this->orderData($product, ['quantity' => 3]))
            ->assertStatus(409)
            ->assertJsonPath('message', 'สินค้าเหลือ 1 ชิ้น กรุณาลดจำนวน');
    }

    public function test_order_rules(): void
    {
        [$seller, $shop] = $this->seller();
        $product = $this->product($shop);
        $buyer = User::factory()->create();

        // สินค้าของตัวเอง
        Sanctum::actingAs($seller);
        $this->postJson('/api/orders', $this->orderData($product))->assertUnprocessable();

        Sanctum::actingAs($buyer);

        // ส่งพัสดุต้องมีที่อยู่
        $this->postJson('/api/orders', $this->orderData($product, ['address' => '']))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('address');

        // เงินสดใช้กับส่งพัสดุไม่ได้
        $this->postJson('/api/orders', $this->orderData($product, ['payment_method' => 'cash']))
            ->assertUnprocessable()
            ->assertJsonPath('message', 'วิธีชำระเงินนี้ใช้กับวิธีรับสินค้าที่เลือกไม่ได้');

        // ร้านไม่ได้เปิดวิธีนี้
        $this->postJson('/api/orders', $this->orderData($product, ['delivery_method' => 'meetup', 'payment_method' => 'cash']))
            ->assertUnprocessable();

        // ไม่มีราคา = สอบถามราคา
        $askPrice = $this->product($shop, ['price' => null]);
        $this->getJson("/api/market/products/{$askPrice->id}")
            ->assertOk()
            ->assertJsonPath('product.order.available', false)
            ->assertJsonPath('product.order.reason', 'สินค้านี้ให้สอบถามราคากับร้านก่อน');

        // ร้านที่ยังไม่ตั้งวิธีรับเงิน
        [, $noPayShop] = $this->seller(['payment_methods' => null]);
        $noPayProduct = $this->product($noPayShop);

        $this->getJson("/api/market/products/{$noPayProduct->id}")
            ->assertJsonPath('product.order.available', false);
        $this->postJson('/api/orders', $this->orderData($noPayProduct))->assertUnprocessable();

        // พร้อมเพย์ที่ไม่มีเลข ไม่นับว่าเปิดรับ
        $noPromptPay = Shop::make(['payment_methods' => ['promptpay'], 'delivery_methods' => ['shipping'], 'status' => Shop::STATUS_ACTIVE]);
        $this->assertFalse($noPromptPay->acceptsOrders());

        $this->getJson("/api/market/products/{$product->id}")
            ->assertJsonPath('product.order.available', true)
            ->assertJsonPath('product.stock', 5);

        // สั่งค้างไม่จ่ายได้ไม่เกิน 3 รายการต่อร้าน
        $this->placeOrder($buyer, $product, ['quantity' => 1]);
        $this->placeOrder($buyer, $product, ['quantity' => 1]);
        $this->placeOrder($buyer, $product, ['quantity' => 1]);

        $this->postJson('/api/orders', $this->orderData($product, ['quantity' => 1]))->assertStatus(429);
    }

    public function test_only_the_buyer_and_shop_can_see_and_act(): void
    {
        [$seller, $shop] = $this->seller();
        $product = $this->product($shop);
        $buyer = User::factory()->create();

        $order = $this->placeOrder($buyer, $product);

        Sanctum::actingAs(User::factory()->create());
        $this->getJson("/api/orders/{$order->id}")->assertNotFound();
        $this->postJson("/api/orders/{$order->id}/cancel", ['reason' => 'x'])->assertNotFound();

        // ผู้ซื้อส่งสินค้าเองไม่ได้ / ร้านแนบสลิปแทนไม่ได้
        Sanctum::actingAs($buyer);
        $this->postJson("/api/orders/{$order->id}/ship")->assertStatus(409);

        Sanctum::actingAs($seller);
        $this->post("/api/orders/{$order->id}/slip", ['slip' => $this->fakePng('slip.png')], ['Accept' => 'application/json'])
            ->assertStatus(409);

        // ร้านยกเลิกต้องบอกเหตุผล
        $this->postJson("/api/orders/{$order->id}/cancel")->assertJsonValidationErrors('reason');
        $this->postJson("/api/orders/{$order->id}/cancel", ['reason' => 'ของหมดหน้าร้าน'])
            ->assertOk()
            ->assertJsonPath('order.cancelled_by', Order::BY_SELLER);

        $this->assertSame(5, $product->refresh()->stock);
        $this->assertTrue(
            AppNotification::where('user_id', $buyer->id)->where('title', 'คำสั่งซื้อถูกยกเลิก')->exists()
        );
    }

    public function test_buyer_can_cancel_a_paid_order_the_shop_never_sends(): void
    {
        [$seller, $shop] = $this->seller();
        $product = $this->product($shop);
        $buyer = User::factory()->create();

        $order = $this->placeOrder($buyer, $product);
        $order->attachSlip($this->fakePng('slip.png'));

        // โอนแล้ว ร้านยังไม่เกินกำหนดส่ง → ยกเลิกเองไม่ได้
        Sanctum::actingAs($buyer);
        $this->getJson("/api/orders/{$order->id}")->assertJsonPath('order.actions', []);

        $order->forceFill(['paid_at' => now()->subDays(4)])->save();

        $this->getJson("/api/orders/{$order->id}")->assertJsonPath('order.actions', ['cancel']);

        $this->postJson("/api/orders/{$order->id}/cancel", ['reason' => 'ร้านไม่ส่งของ'])->assertOk();

        $this->assertTrue(
            AppNotification::where('user_id', $seller->id)
                ->where('message', 'like', '%กรุณาคืนเงินให้ลูกค้า%')
                ->exists()
        );
    }

    public function test_stale_orders_expire_on_their_own(): void
    {
        [$seller, $shop] = $this->seller();
        $product = $this->product($shop);
        $buyer = User::factory()->create();

        $unpaid = $this->placeOrder($buyer, $product, ['quantity' => 1]);
        $unpaid->forceFill(['payment_due_at' => now()->subMinute()])->save();

        $delivered = $this->placeOrder($buyer, $product, ['quantity' => 1]);
        $delivered->forceFill(['status' => Order::STATUS_SHIPPED, 'shipped_at' => now()->subDays(8)])->save();

        Sanctum::actingAs($seller);
        $this->getJson('/api/my-shop/orders')->assertOk();

        $this->assertSame(Order::STATUS_CANCELLED, $unpaid->refresh()->status);
        $this->assertSame(Order::BY_SYSTEM, $unpaid->cancelled_by);
        $this->assertSame(Order::STATUS_COMPLETED, $delivered->refresh()->status);

        // รายการที่ยกเลิกคืนสต็อก
        $this->assertSame(4, $product->refresh()->stock);
    }

    public function test_payment_settings_stay_private(): void
    {
        [$seller, $shop] = $this->seller();

        Sanctum::actingAs(User::factory()->create());

        $public = $this->getJson("/api/market/shops/{$shop->id}")
            ->assertOk()
            ->assertJsonPath('shop.accepts_orders', true)
            ->json('shop');

        $this->assertArrayNotHasKey('bank_account_number', $public);
        $this->assertArrayNotHasKey('promptpay_id', $public);

        Sanctum::actingAs($seller);

        $this->getJson('/api/my-shop')
            ->assertJsonPath('shop.bank_account_number', '1234567890')
            ->assertJsonPath('shop.promptpay_id', '0899999999');

        // แอปเวอร์ชันเก่า (ไม่ส่ง payment_settings) ไม่ลบข้อมูลรับเงิน
        $base = [
            'name' => $shop->name,
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'delivery_methods' => ['shipping'],
        ];

        $this->postJson('/api/my-shop/update', $base)->assertOk();
        $this->assertSame('1234567890', $shop->refresh()->bank_account_number);

        // ตั้งค่าใหม่: เลือกธนาคารต้องกรอกครบ
        $this->postJson('/api/my-shop/update', [...$base, 'payment_settings' => 1, 'payment_methods' => ['bank']])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['bank_name', 'bank_account_number', 'bank_account_name']);

        $this->postJson('/api/my-shop/update', [
            ...$base,
            'payment_settings' => 1,
            'payment_methods' => ['promptpay', 'cod'],
            'promptpay_id' => '081-234-5678',
            'bank_account_name' => 'สมหญิง ใจดี',
        ])->assertOk()->assertJsonPath('shop.accepts_orders', true);

        $this->assertSame('0812345678', $shop->refresh()->promptpay_id);
        $this->assertSame(['promptpay', 'cod'], $shop->payment_methods);

        $this->postJson('/api/my-shop/update', [...$base, 'payment_settings' => 1, 'payment_methods' => ['promptpay'], 'promptpay_id' => '12345', 'bank_account_name' => 'x'])
            ->assertJsonValidationErrors('promptpay_id');
    }

    public function test_seller_sets_stock_shipping_and_card_video(): void
    {
        [$seller, $shop] = $this->seller();
        $product = $this->product($shop);
        $product->images()->create(['path' => 'product_images/a.png', 'sort' => 0]);

        Sanctum::actingAs($seller);

        $this->post("/api/my-shop/products/{$product->id}/update", [
            'title' => $product->title,
            'price' => 120,
            'category' => 'produce',
            'stock' => 12,
            'shipping_fee' => '',
            'card_media' => 'video',
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('product.stock', 12)
            ->assertJsonPath('product.shipping_fee', null)
            ->assertJsonPath('product.card_media', 'video');

        // แอปเวอร์ชันเก่าไม่ส่ง stock → ไม่เปลี่ยน
        $this->post("/api/my-shop/products/{$product->id}/update", [
            'title' => $product->title,
            'price' => 120,
            'category' => 'produce',
        ], ['Accept' => 'application/json'])->assertOk()->assertJsonPath('product.stock', 12);

        Sanctum::actingAs(User::factory()->create());

        // ยังไม่มีวิดีโอ → การ์ดใช้รูป
        $this->getJson('/api/market/products')->assertJsonMissingPath('products.0.card_video_url');

        $product->refresh()->forceFill(['video_path' => 'product_videos/1/a.mp4', 'video_thumbnail_path' => 'product_videos/1/a.jpg'])->save();

        $card = $this->getJson('/api/market/products')->json('products.0');
        $this->assertNotNull($card['card_video_url']);
        $this->assertFalse($card['sold_out']);

        $product->forceFill(['stock' => 0])->save();
        $this->getJson('/api/market/products')->assertJsonPath('products.0.sold_out', true);
    }

    public function test_deleting_the_shop_removes_order_slips(): void
    {
        [, $shop] = $this->seller();
        $product = $this->product($shop);
        $buyer = User::factory()->create();

        $order = $this->placeOrder($buyer, $product);
        $order->attachSlip($this->fakePng('slip.png'));

        $this->assertCount(1, Storage::disk(MediaStorage::disk())->allFiles('order_slips'));

        $shop->refresh()->delete();

        $this->assertCount(0, Storage::disk(MediaStorage::disk())->allFiles('order_slips'));
        $this->assertSame(0, Order::count());
    }
}
