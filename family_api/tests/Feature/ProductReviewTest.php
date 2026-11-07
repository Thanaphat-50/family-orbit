<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductReview;
use App\Models\Shop;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

// รีวิวสินค้าจากผู้ซื้อจริง + แท็บคำสั่งซื้อตามสถานะ
class ProductReviewTest extends TestCase
{
    use RefreshDatabase;

    private Shop $shop;
    private Product $product;
    private User $buyer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->shop = Shop::create([
            'user_id' => User::factory()->create()->id,
            'name' => 'ร้านทดสอบ',
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => Shop::STATUS_ACTIVE,
            'delivery_methods' => ['storefront'],
            'payment_methods' => ['cash'],
        ]);

        $this->product = $this->shop->products()->create([
            'title' => 'มะม่วง',
            'price' => 100,
            'stock' => 10,
            'category' => 'produce',
            'status' => Product::STATUS_ACTIVE,
        ]);

        $this->buyer = User::factory()->create();
    }

    private function order(): Order
    {
        Sanctum::actingAs($this->buyer);

        $id = $this->postJson('/api/orders', [
            'product_id' => $this->product->id,
            'quantity' => 1,
            'delivery_method' => 'storefront',
            'payment_method' => 'cash',
            'recipient_name' => 'ก',
            'recipient_phone' => '0811111111',
        ])->assertCreated()->json('order.id');

        return Order::findOrFail($id);
    }

    public function test_only_buyers_of_completed_orders_can_review(): void
    {
        $order = $this->order();

        // ยังไม่ได้รับสินค้า
        $this->postJson("/api/orders/{$order->id}/reviews", ['product_id' => $this->product->id, 'rating' => 5])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'รีวิวได้เมื่อได้รับสินค้าแล้ว');

        $order->forceFill(['status' => Order::STATUS_COMPLETED])->save();

        // คนอื่นรีวิวแทนไม่ได้
        Sanctum::actingAs(User::factory()->create());
        $this->postJson("/api/orders/{$order->id}/reviews", ['product_id' => $this->product->id, 'rating' => 1])
            ->assertNotFound();

        Sanctum::actingAs($this->buyer);

        $this->postJson("/api/orders/{$order->id}/reviews", [
            'product_id' => $this->product->id,
            'rating' => 4,
            'comment' => 'หวานดี',
        ])->assertOk()->assertJsonPath("order.my_reviews.{$this->product->id}.rating", 4);

        // แก้รีวิวเดิม ไม่เพิ่มใหม่
        $this->postJson("/api/orders/{$order->id}/reviews", ['product_id' => $this->product->id, 'rating' => 5])
            ->assertOk();

        $this->assertSame(1, ProductReview::count());
        $this->assertSame(5, ProductReview::first()->rating);
        $this->assertSame(1, AppNotification::where('type', 'shop_review')->count());

        // สินค้าที่ไม่ได้อยู่ในคำสั่งซื้อ
        $this->postJson("/api/orders/{$order->id}/reviews", ['product_id' => 999, 'rating' => 5])->assertNotFound();
    }

    public function test_reviews_show_on_the_product_page(): void
    {
        $order = $this->order();
        $order->forceFill(['status' => Order::STATUS_COMPLETED])->save();

        $this->postJson("/api/orders/{$order->id}/reviews", ['product_id' => $this->product->id, 'rating' => 4, 'comment' => 'ดี']);

        // รีวิวที่ผู้ดูแลซ่อนแล้ว ไม่แสดงและไม่นับคะแนน
        $hidden = ProductReview::create([
            'product_id' => $this->product->id,
            'order_id' => $this->order()->id,
            'user_id' => User::factory()->create()->id,
            'shop_id' => $this->shop->id,
            'rating' => 1,
            'hidden_at' => now(),
        ]);

        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/market/products/{$this->product->id}")
            ->assertOk()
            ->assertJsonPath('review_summary.count', 1)
            ->assertJsonPath('review_summary.average', 4)
            ->assertJsonCount(1, 'reviews')
            ->assertJsonPath('reviews.0.verified_purchase', true);

        $this->getJson("/api/market/products/{$this->product->id}/reviews")
            ->assertOk()
            ->assertJsonCount(1, 'reviews');

        $this->assertNotNull($hidden->hidden_at);
    }

    public function test_buyer_order_tabs_and_counts(): void
    {
        $preparing = $this->order();
        $shipped = $this->order();
        $shipped->forceFill(['status' => Order::STATUS_SHIPPED, 'shipped_at' => now()])->save();

        $this->getJson('/api/orders?filter=to_ship')
            ->assertOk()
            ->assertJsonCount(1, 'orders')
            ->assertJsonPath('orders.0.id', $preparing->id)
            ->assertJsonPath('counts.to_ship', 1)
            ->assertJsonPath('counts.shipping', 1)
            ->assertJsonPath('counts.to_pay', 0);

        $this->getJson('/api/orders?filter=shipping')->assertJsonPath('orders.0.id', $shipped->id);
        $this->getJson('/api/orders?filter=nope')->assertUnprocessable();
    }
}
