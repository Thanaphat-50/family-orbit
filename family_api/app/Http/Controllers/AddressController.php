<?php

namespace App\Http\Controllers;

use App\Models\Address;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

// =======================================================
// ที่อยู่จัดส่งของฉัน (ไม่เกิน 10 ที่อยู่, ที่อยู่หลัก 1 ที่)
// =======================================================

class AddressController extends Controller
{
    private const MAX_ADDRESSES = 10;

    public function index(Request $request)
    {
        return response()->json([
            'status' => true,
            'addresses' => $this->list($request->user()->id),
        ]);
    }

    public function store(Request $request)
    {
        $user = $request->user();

        if (Address::where('user_id', $user->id)->count() >= self::MAX_ADDRESSES) {
            return response()->json([
                'status' => false,
                'message' => 'บันทึกที่อยู่ได้ไม่เกิน ' . self::MAX_ADDRESSES . ' ที่',
            ], 422);
        }

        $data = $request->validate($this->rules(), $this->messages());

        $first = !Address::where('user_id', $user->id)->exists();

        $address = DB::transaction(function () use ($user, $data, $first) {
            $makeDefault = $first || !empty($data['is_default']);

            if ($makeDefault) {
                Address::where('user_id', $user->id)->update(['is_default' => false]);
            }

            return Address::create([
                ...$this->fields($data),
                'user_id' => $user->id,
                'is_default' => $makeDefault,
            ]);
        });

        return response()->json([
            'status' => true,
            'message' => 'บันทึกที่อยู่แล้ว',
            'address' => $address->toPayload(),
            'addresses' => $this->list($user->id),
        ], 201);
    }

    public function update(Request $request, Address $address)
    {
        $user = $request->user();

        if ((int) $address->user_id !== (int) $user->id) {
            return $this->notFound();
        }

        $data = $request->validate($this->rules(), $this->messages());

        DB::transaction(function () use ($user, $address, $data) {
            if (!empty($data['is_default'])) {
                Address::where('user_id', $user->id)->update(['is_default' => false]);
                $address->is_default = true;
            }

            $address->fill($this->fields($data))->save();
        });

        return response()->json([
            'status' => true,
            'message' => 'บันทึกที่อยู่แล้ว',
            'address' => $address->refresh()->toPayload(),
            'addresses' => $this->list($user->id),
        ]);
    }

    public function destroy(Request $request, Address $address)
    {
        $user = $request->user();

        if ((int) $address->user_id !== (int) $user->id) {
            return $this->notFound();
        }

        DB::transaction(function () use ($user, $address) {
            $wasDefault = $address->is_default;

            $address->delete();

            // ลบที่อยู่หลัก → ใช้ที่อยู่ล่าสุดเป็นที่อยู่หลักแทน
            if ($wasDefault) {
                Address::where('user_id', $user->id)->latest('id')->first()?->update(['is_default' => true]);
            }
        });

        return response()->json([
            'status' => true,
            'message' => 'ลบที่อยู่แล้ว',
            'addresses' => $this->list($user->id),
        ]);
    }

    private function list(int $userId)
    {
        return Address::where('user_id', $userId)
            ->orderByDesc('is_default')
            ->latest('id')
            ->get()
            ->map(fn (Address $address) => $address->toPayload())
            ->values();
    }

    private function rules(): array
    {
        return [
            'recipient_name' => 'required|string|max:100',
            'phone' => ['required', 'string', 'regex:/^\+?[0-9][0-9\s\-]{7,18}$/'],
            'address_line' => 'required|string|max:255',
            'subdistrict' => 'required|string|max:80',
            'district' => 'required|string|max:80',
            'province' => ['required', Rule::in(config('market.provinces'))],
            'postcode' => ['required', 'regex:/^[1-9][0-9]{4}$/'],
            'is_default' => 'nullable|boolean',
        ];
    }

    private function messages(): array
    {
        return [
            'recipient_name.*' => 'กรุณาใส่ชื่อผู้รับ (ไม่เกิน 100 ตัวอักษร)',
            'phone.required' => 'กรุณาใส่เบอร์โทร',
            'phone.regex' => 'เบอร์โทรไม่ถูกต้อง',
            'address_line.*' => 'กรุณาใส่บ้านเลขที่ ซอย ถนน',
            'subdistrict.*' => 'กรุณาใส่ตำบล / แขวง',
            'district.*' => 'กรุณาใส่อำเภอ / เขต',
            'province.*' => 'กรุณาเลือกจังหวัด',
            'postcode.*' => 'รหัสไปรษณีย์ต้องเป็นตัวเลข 5 หลัก',
        ];
    }

    private function fields(array $data): array
    {
        return [
            'recipient_name' => trim($data['recipient_name']),
            'phone' => preg_replace('/[\s\-]/', '', $data['phone']),
            'address_line' => trim($data['address_line']),
            'subdistrict' => trim($data['subdistrict']),
            'district' => trim($data['district']),
            'province' => $data['province'],
            'postcode' => $data['postcode'],
        ];
    }

    private function notFound()
    {
        return response()->json([
            'status' => false,
            'message' => 'ไม่พบที่อยู่นี้',
        ], 404);
    }
}
