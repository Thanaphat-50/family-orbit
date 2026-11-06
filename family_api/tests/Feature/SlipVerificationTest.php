<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\PaymentTransaction;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use App\Services\SlipVerifier;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

// ตรวจสลิปอัตโนมัติ (EasySlip จำลองด้วย Http::fake)
class SlipVerificationTest extends TestCase
{
    use FakesImages, RefreshDatabase;

    private Order $order;
    private User $buyer;
    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake(MediaStorage::disk());

        config(['market.slip_verify.easyslip_key' => 'test-key']);

        $this->seller = User::factory()->create();

        $shop = Shop::create([
            'user_id' => $this->seller->id,
            'name' => 'ร้านทดสอบ',
            'category' => 'produce',
            'phone' => '0812345678',
            'province' => 'เชียงใหม่',
            'status' => Shop::STATUS_ACTIVE,
            'delivery_methods' => ['storefront'],
            'payment_methods' => ['promptpay', 'bank'],
            'promptpay_id' => '0899999999',
            'bank_name' => 'ธนาคารกสิกรไทย',
            'bank_account_number' => '1234567890',
            'bank_account_name' => 'ร้านทดสอบ',
        ]);

        $product = $shop->products()->create([
            'title' => 'มะม่วง',
            'price' => 100,
            'stock' => 10,
            'category' => 'produce',
            'status' => Product::STATUS_ACTIVE,
        ]);

        $this->buyer = User::factory()->create();

        Sanctum::actingAs($this->buyer);

        $id = $this->postJson('/api/orders', [
            'product_id' => $product->id,
            'quantity' => 2,
            'delivery_method' => 'storefront',
            'payment_method' => 'promptpay',
            'recipient_name' => 'ก',
            'recipient_phone' => '0811111111',
        ])->assertCreated()->json('order.id');

        $this->order = Order::findOrFail($id);
    }

    private function slipResponse(array $overrides = []): array
    {
        return [
            'success' => true,
            'data' => [
                'isDuplicate' => false,
                'amountInSlip' => $overrides['amount'] ?? 200,
                'rawSlip' => [
                    'transRef' => $overrides['transRef'] ?? 'TX-1',
                    'date' => $overrides['date'] ?? now()->toIso8601String(),
                    'amount' => ['amount' => $overrides['amount'] ?? 200],
                    'receiver' => ['account' => $overrides['receiver'] ?? [
                        'proxy' => ['type' => 'MSISDN', 'account' => '089xxxx999'],
                    ]],
                ],
                ...($overrides['data'] ?? []),
            ],
        ];
    }

    private function upload()
    {
        return $this->post("/api/orders/{$this->order->id}/slip", [
            'slip' => $this->fakePng('slip.png'),
        ], ['Accept' => 'application/json']);
    }

    public function test_valid_slip_is_paid_immediately(): void
    {
        Http::fake(['api.easyslip.com/*' => Http::response($this->slipResponse())]);

        $this->upload()
            ->assertOk()
            ->assertJsonPath('order.status', Order::STATUS_PREPARING)
            ->assertJsonPath('order.payments.0.verified_by_system', true);

        $this->assertNotNull($this->order->refresh()->paid_at);

        // ส่งคีย์แบบ Bearer + ยอดที่ต้องชำระ + ตรวจสลิปซ้ำ
        Http::assertSent(fn (Request $request) => $request->hasHeader('Authorization', 'Bearer test-key')
            && str_contains($request->url(), '/v2/verify/bank'));
    }

    public function test_bank_transfer_slip_checks_the_account(): void
    {
        $this->order->forceFill(['payment_method' => 'bank'])->save();

        Http::fake(['api.easyslip.com/*' => Http::response($this->slipResponse([
            // บัญชีร้าน 123-4-56789-0
            'receiver' => ['bank' => ['type' => 'BANKAC', 'account' => 'xxx-x-x6789-x']],
        ]))]);

        $this->upload()->assertOk()->assertJsonPath('order.status', Order::STATUS_PREPARING);
    }

    public function test_bad_slips_are_rejected_and_not_kept(): void
    {
        $cases = [
            'น้อยกว่ายอดที่ต้องชำระ' => $this->slipResponse(['amount' => 150, 'transRef' => 'A']),
            'บัญชีที่ไม่ใช่ของร้าน' => $this->slipResponse([
                'transRef' => 'B',
                'receiver' => ['proxy' => ['type' => 'MSISDN', 'account' => '081xxxx111']],
            ]),
            'ถูกใช้ชำระไปแล้ว' => $this->slipResponse(['transRef' => 'C', 'data' => ['isDuplicate' => true]]),
            'โอนก่อนสั่งซื้อ' => $this->slipResponse(['transRef' => 'D', 'date' => now()->subDay()->toIso8601String()]),
            'ไม่พบรายการโอน' => ['success' => false, 'error' => ['code' => 'SLIP_NOT_FOUND', 'message' => 'x']],
        ];

        foreach ($cases as $expected => $body) {
            Http::fake(['api.easyslip.com/*' => Http::response($body, ($body['success'] ?? false) ? 200 : 404)]);

            $response = $this->upload()
                ->assertUnprocessable()
                ->assertJsonPath('code', 'slip_rejected')
                ->assertJsonPath('order.status', Order::STATUS_AWAITING_PAYMENT);

            $this->assertStringContainsString($expected, $response->json('message'));

            // ล้างคำตอบจำลองเดิมก่อนกรณีถัดไป
            Http::swap(new \Illuminate\Http\Client\Factory);
        }

        $this->assertNull($this->order->refresh()->paid_at);
        $this->assertCount(0, Storage::disk(MediaStorage::disk())->allFiles('order_slips'));
        $this->assertSame(5, PaymentTransaction::where('status', 'rejected')->count());
    }

    public function test_slip_used_by_another_order_is_rejected(): void
    {
        $other = $this->order->replicate(['code']);
        $other->code = 'OR-OTHER';
        $other->save();

        PaymentTransaction::create([
            'order_id' => $other->id,
            'method' => 'promptpay',
            'amount' => 200,
            'status' => PaymentTransaction::STATUS_VERIFIED,
            'provider' => 'easyslip',
            'trans_ref' => 'TX-SAME',
        ]);

        Http::fake(['api.easyslip.com/*' => Http::response($this->slipResponse(['transRef' => 'TX-SAME']))]);

        $this->upload()->assertUnprocessable()->assertJsonPath('code', 'slip_rejected');
    }

    public function test_unavailable_check_falls_back_to_the_shop(): void
    {
        Http::fake(['api.easyslip.com/*' => Http::response(['success' => false, 'error' => ['code' => 'QUOTA_EXCEEDED']], 403)]);

        $this->upload()
            ->assertOk()
            ->assertJsonPath('order.status', Order::STATUS_PAYMENT_REVIEW)
            ->assertJsonPath('order.payments.0.status', 'review');

        // ร้านเช็กยอดแล้วยืนยัน
        Sanctum::actingAs($this->seller);

        $this->getJson('/api/my-shop/orders?filter=todo')->assertJsonPath('todo', 1);

        $this->postJson("/api/orders/{$this->order->id}/confirm-payment")
            ->assertOk()
            ->assertJsonPath('order.status', Order::STATUS_PREPARING);

        // ผู้ซื้อยืนยันรับเงินแทนร้านไม่ได้
        Sanctum::actingAs($this->buyer);
        $this->postJson("/api/orders/{$this->order->id}/confirm-payment")->assertStatus(409);
    }

    public function test_overpaid_or_unknown_receiver_goes_to_review(): void
    {
        Http::fake(['api.easyslip.com/*' => Http::response($this->slipResponse(['amount' => 500]))]);

        $this->upload()->assertOk()->assertJsonPath('order.status', Order::STATUS_PAYMENT_REVIEW);
    }

    public function test_masked_account_matching(): void
    {
        $this->assertTrue(SlipVerifier::maskedMatches('xxx-x-x5678-x', '123-4-55678-9'));
        $this->assertFalse(SlipVerifier::maskedMatches('xxx-x-x5678-x', '1234511119'));
        $this->assertTrue(SlipVerifier::maskedMatches('089xxxx999', '0899999999'));
        $this->assertNull(SlipVerifier::maskedMatches('xxxxxxxx9', '0899999999'));
        $this->assertNull(SlipVerifier::maskedMatches(null, '0899999999'));
    }
}
