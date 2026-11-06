<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

// ที่อยู่จัดส่งที่ผู้ใช้บันทึกไว้ (เลือกใช้ซ้ำได้ตอนสั่งซื้อ)
class Address extends Model
{
    protected $fillable = [
        'user_id',
        'recipient_name',
        'phone',
        'address_line',
        'subdistrict',
        'district',
        'province',
        'postcode',
        'is_default',
    ];

    protected $casts = [
        'is_default' => 'boolean',
    ];

    // ที่อยู่แบบบรรทัดเดียว เก็บลงคำสั่งซื้อ
    public function fullAddress(): string
    {
        return implode(' ', array_filter([
            $this->address_line,
            'ต.' . $this->subdistrict,
            'อ.' . $this->district,
            'จ.' . $this->province,
            $this->postcode,
        ]));
    }

    public function toPayload(): array
    {
        return [
            ...$this->only([
                'id', 'recipient_name', 'phone', 'address_line',
                'subdistrict', 'district', 'province', 'postcode', 'is_default',
            ]),
            'full_address' => $this->fullAddress(),
        ];
    }
}
