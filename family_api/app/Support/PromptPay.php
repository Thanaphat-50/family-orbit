<?php

namespace App\Support;

use InvalidArgumentException;

// =======================================================
// ข้อความสำหรับ QR พร้อมเพย์ (มาตรฐาน EMVCo / Thai QR Payment)
// แอปนำข้อความนี้ไปสร้างรูป QR เอง
// =======================================================

class PromptPay
{
    private const AID = 'A000000677010111';

    // id: เบอร์มือถือ 10 หลัก หรือเลข 13 หลัก (บัตรประชาชน / ผู้เสียภาษี)
    public static function payload(string $id, float $amount): string
    {
        $digits = preg_replace('/\D/', '', $id);

        if (strlen($digits) === 10 && str_starts_with($digits, '0')) {
            // 0812345678 → 0066812345678
            $account = self::field('01', '0066' . substr($digits, 1));
        } elseif (strlen($digits) === 13) {
            $account = self::field('02', $digits);
        } else {
            throw new InvalidArgumentException('PromptPay ID must be a 10-digit phone or a 13-digit ID.');
        }

        $data = self::field('00', '01')
            // 12 = QR ใช้ครั้งเดียวพร้อมจำนวนเงิน
            . self::field('01', '12')
            . self::field('29', self::field('00', self::AID) . $account)
            . self::field('53', '764')
            . self::field('54', number_format($amount, 2, '.', ''))
            . self::field('58', 'TH')
            . '6304';

        return $data . self::crc16($data);
    }

    public static function isValidId(?string $id): bool
    {
        $digits = preg_replace('/\D/', '', (string) $id);

        return (strlen($digits) === 10 && str_starts_with($digits, '0')) || strlen($digits) === 13;
    }

    // เบอร์/เลขที่แสดงให้ผู้โอนเห็น (ซ่อนกลาง)
    public static function maskedId(string $id): string
    {
        $digits = preg_replace('/\D/', '', $id);

        return substr($digits, 0, 3) . str_repeat('x', max(0, strlen($digits) - 7)) . substr($digits, -4);
    }

    private static function field(string $tag, string $value): string
    {
        return $tag . str_pad((string) strlen($value), 2, '0', STR_PAD_LEFT) . $value;
    }

    // CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF)
    public static function crc16(string $data): string
    {
        $crc = 0xFFFF;

        for ($i = 0; $i < strlen($data); $i++) {
            $crc ^= ord($data[$i]) << 8;

            for ($bit = 0; $bit < 8; $bit++) {
                $crc = ($crc & 0x8000) ? (($crc << 1) ^ 0x1021) : ($crc << 1);
                $crc &= 0xFFFF;
            }
        }

        return strtoupper(str_pad(dechex($crc), 4, '0', STR_PAD_LEFT));
    }
}
