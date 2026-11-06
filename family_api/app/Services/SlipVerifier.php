<?php

namespace App\Services;

use App\Models\Order;
use App\Models\PaymentTransaction;
use App\Models\Shop;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

// =======================================================
// ตรวจสลิปโอนเงินอัตโนมัติ (EasySlip API v2: POST /v2/verify/bank)
// - EasySlip อ่าน QR บนสลิปแล้วตรวจกับข้อมูลธนาคาร + บอกว่าเป็นสลิปซ้ำหรือไม่
// - ระบบเทียบยอดเงิน วันที่โอน และบัญชีผู้รับกับบัญชีของร้านเอง
// ผลลัพธ์:
//   verified = ผ่าน → ชำระเงินแล้ว
//   rejected = ไม่ผ่านแน่นอน (สลิปปลอม/ยอดไม่ครบ/บัญชีอื่น/สลิปซ้ำ) → ผู้ซื้อแนบใหม่
//   review   = ตรวจอัตโนมัติไม่ได้ (ยังไม่ตั้งคีย์/ระบบล่ม/ข้อมูลไม่พอ) → ร้านตรวจเอง
// =======================================================

class SlipVerifier
{
    // สลิปที่โอนก่อนสั่งซื้อเกินเท่านี้ = สลิปเก่า
    private const EARLY_MINUTES = 10;

    public function enabled(): bool
    {
        return filled(config('market.slip_verify.easyslip_key'));
    }

    /**
     * @return array{status: string, provider: string, reason: ?string, trans_ref: ?string,
     *               slip_amount: ?float, slip_date: ?Carbon, receiver_account: ?string}
     */
    public function check(string $contents, string $filename, Order $order): array
    {
        if (!$this->enabled()) {
            return $this->result(PaymentTransaction::STATUS_REVIEW, 'manual', 'ร้านจะตรวจยอดเงินในบัญชีแล้วยืนยันให้');
        }

        $total = (float) $order->total;

        try {
            $response = Http::withToken(config('market.slip_verify.easyslip_key'))
                ->acceptJson()
                ->timeout(20)
                ->attach('image', $contents, $filename)
                ->post(config('market.slip_verify.easyslip_url'), [
                    'checkDuplicate' => 'true',
                    'matchAmount' => number_format($total, 2, '.', ''),
                    'remark' => $order->code,
                ]);
        } catch (Throwable $e) {
            Log::warning('Slip verification failed to connect', ['order_id' => $order->id, 'error' => $e->getMessage()]);

            return $this->unavailable();
        }

        $json = $response->json() ?? [];

        if (!$response->successful() || ($json['success'] ?? false) !== true) {
            $code = $json['error']['code'] ?? null;

            if (!in_array($code, ['SLIP_NOT_FOUND', 'INVALID_IMAGE_TYPE', 'INVALID_IMAGE_FORMAT', 'IMAGE_SIZE_TOO_LARGE', 'VALIDATION_ERROR', 'SLIP_PENDING'], true)) {
                Log::warning('Slip verification error', ['order_id' => $order->id, 'status' => $response->status(), 'code' => $code]);
            }

            return match ($code) {
                'SLIP_NOT_FOUND' => $this->rejected('ไม่พบรายการโอนนี้ในระบบธนาคาร กรุณาแนบสลิปจริงจากแอปธนาคาร'),
                'INVALID_IMAGE_TYPE', 'INVALID_IMAGE_FORMAT', 'VALIDATION_ERROR' => $this->rejected('อ่าน QR บนสลิปไม่ได้ กรุณาแนบรูปสลิปที่เห็น QR ชัดเจน'),
                'IMAGE_SIZE_TOO_LARGE' => $this->rejected('รูปสลิปใหญ่เกินไป กรุณาแนบรูปที่เล็กลง'),
                // ธนาคารบางแห่งยังไม่ยืนยันรายการในไม่กี่นาทีแรก
                'SLIP_PENDING' => $this->result(PaymentTransaction::STATUS_REVIEW, 'easyslip', 'ธนาคารยังไม่ยืนยันรายการโอน ร้านจะตรวจยอดเงินในบัญชีแล้วยืนยันให้'),
                default => $this->unavailable(),
            };
        }

        $data = $json['data'] ?? [];
        $slip = $data['rawSlip'] ?? [];

        $transRef = isset($slip['transRef']) ? (string) $slip['transRef'] : null;
        $amount = (float) ($data['amountInSlip'] ?? $slip['amount']['amount'] ?? 0);
        $date = isset($slip['date']) ? Carbon::parse($slip['date']) : null;

        $receiver = $slip['receiver']['account'] ?? [];
        $receiverAccount = $receiver['proxy']['account'] ?? $receiver['bank']['account'] ?? null;

        $details = [
            'trans_ref' => $transRef,
            'slip_amount' => $amount,
            'slip_date' => $date,
            'receiver_account' => $receiverAccount === null ? null : mb_substr((string) $receiverAccount, 0, 40),
        ];

        // สลิปเดียวกันกับที่เคยแนบในคำสั่งซื้อนี้ (แนบซ้ำ) ไม่นับว่าซ้ำ
        $usedHere = $transRef !== null
            && PaymentTransaction::where('order_id', $order->id)->where('trans_ref', $transRef)->exists();

        $usedElsewhere = $transRef !== null && PaymentTransaction::where('trans_ref', $transRef)
            ->where('order_id', '!=', $order->id)
            ->whereIn('status', [PaymentTransaction::STATUS_VERIFIED, PaymentTransaction::STATUS_CONFIRMED, PaymentTransaction::STATUS_REVIEW])
            ->exists();

        if ($usedElsewhere || (($data['isDuplicate'] ?? false) === true && !$usedHere)) {
            return $this->rejected('สลิปนี้ถูกใช้ชำระไปแล้ว กรุณาแนบสลิปของการโอนครั้งนี้', $details);
        }

        if ($date && $date->lt($order->created_at->copy()->subMinutes(self::EARLY_MINUTES))) {
            return $this->rejected('สลิปนี้โอนก่อนสั่งซื้อ กรุณาแนบสลิปของการโอนครั้งนี้', $details);
        }

        if ($amount + 0.009 < $total) {
            return $this->rejected(
                'ยอดโอน ' . Order::baht($amount) . ' น้อยกว่ายอดที่ต้องชำระ ' . Order::baht($total),
                $details
            );
        }

        $matches = $this->receiverMatches($receiver, $order->shop, $order->payment_method);

        if ($matches === false) {
            return $this->rejected('สลิปนี้โอนเข้าบัญชีที่ไม่ใช่ของร้าน', $details);
        }

        if ($matches === null) {
            return $this->result(PaymentTransaction::STATUS_REVIEW, 'easyslip', 'ตรวจบัญชีผู้รับจากสลิปไม่ได้ ร้านจะตรวจยอดเงินแล้วยืนยันให้', $details);
        }

        if ($amount - 0.009 > $total) {
            return $this->result(PaymentTransaction::STATUS_REVIEW, 'easyslip', 'ยอดโอนมากกว่ายอดที่ต้องชำระ ร้านจะตรวจสอบแล้วยืนยันให้', $details);
        }

        return $this->result(PaymentTransaction::STATUS_VERIFIED, 'easyslip', null, $details);
    }

    // บัญชีผู้รับในสลิป (ปิดบางหลัก) ตรงกับบัญชีของร้านไหม (null = บอกไม่ได้)
    private function receiverMatches(array $receiver, ?Shop $shop, string $method): ?bool
    {
        if (!$shop) {
            return null;
        }

        $proxy = $receiver['proxy']['account'] ?? null;
        $bank = $receiver['bank']['account'] ?? null;

        if ($method === 'promptpay' && $proxy !== null) {
            return self::maskedMatches($proxy, $shop->promptpay_id);
        }

        if ($bank !== null && filled($shop->bank_account_number)) {
            return self::maskedMatches($bank, $shop->bank_account_number);
        }

        return null;
    }

    // "xxx-x-x5678-x" กับ "1234567890": เทียบเฉพาะหลักที่สลิปแสดง (เรียงจากขวา)
    // แสดงน้อยกว่า 3 หลัก = บอกไม่ได้
    public static function maskedMatches(?string $masked, ?string $actual): ?bool
    {
        $mask = strrev(preg_replace('/[^0-9xX*]/', '', (string) $masked));
        $digits = strrev(preg_replace('/\D/', '', (string) $actual));

        if ($mask === '' || $digits === '') {
            return null;
        }

        $compared = 0;

        for ($i = 0; $i < strlen($mask) && $i < strlen($digits); $i++) {
            if (!ctype_digit($mask[$i])) {
                continue;
            }

            if ($mask[$i] !== $digits[$i]) {
                return false;
            }

            $compared++;
        }

        return $compared >= 3 ? true : null;
    }

    private function unavailable(): array
    {
        return $this->result(PaymentTransaction::STATUS_REVIEW, 'easyslip', 'ระบบตรวจสลิปขัดข้องชั่วคราว ร้านจะตรวจยอดเงินแล้วยืนยันให้');
    }

    private function rejected(string $reason, array $details = []): array
    {
        return $this->result(PaymentTransaction::STATUS_REJECTED, 'easyslip', $reason, $details);
    }

    private function result(string $status, string $provider, ?string $reason, array $details = []): array
    {
        return [
            'status' => $status,
            'provider' => $provider,
            'reason' => $reason,
            'trans_ref' => $details['trans_ref'] ?? null,
            'slip_amount' => $details['slip_amount'] ?? null,
            'slip_date' => $details['slip_date'] ?? null,
            'receiver_account' => $details['receiver_account'] ?? null,
        ];
    }
}
