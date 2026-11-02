<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Throwable;

// =======================================================
// รายละเอียดของตำแหน่ง (หน้าแผนที่)
//
// 1) พื้นที่: หมู่บ้าน/ชุมชน ตำบล อำเภอ จังหวัด
//    จาก OpenStreetMap (Nominatim) ฟรี ไม่ต้องตั้งค่า
//    - นโยบาย Nominatim: ไม่เกิน 1 ครั้ง/วินาที ระบุชื่อแอป และเก็บผลไว้ใช้ซ้ำ
//      → เก็บตามพิกัดที่ปัดแล้ว (~110 เมตร) 7 วัน
//    - แอปต้องแสดง "© OpenStreetMap"
//
// 2) สถานที่ใกล้เคียง: Google Places API (New) Nearby Search
//    ใช้ GOOGLE_MAPS_SERVER_KEY เดียวกับเส้นทาง
//    ต้องเปิด Places API (New) ใน Google Cloud ก่อน (docs/maps-routes-setup.md)
//    - ข้อกำหนดของ Google ห้ามเก็บข้อมูลสถานที่ไว้ → เรียกใหม่ทุกครั้ง
// =======================================================

class PlaceFinder
{
    private const NOMINATIM = 'https://nominatim.openstreetmap.org/reverse';

    private const NEARBY = 'https://places.googleapis.com/v1/places:searchNearby';

    // หาสถานที่ในรัศมีนี้ (เมตร) เรียงจากใกล้สุด
    private const NEARBY_RADIUS = 1000.0;

    private const NEARBY_LIMIT = 6;

    // ประเภทที่แสดงเป็นสถานที่ท่องเที่ยว
    private const TOURIST_TYPES = [
        'tourist_attraction',
        'museum',
        'park',
        'national_park',
        'zoo',
        'aquarium',
        'amusement_park',
        'art_gallery',
        'beach',
        'place_of_worship',
        'hindu_temple',
        'church',
        'mosque',
        'historical_landmark',
    ];

    // Google ตอบว่ายังไม่ได้เปิด Places API → หยุดเรียกสักพัก
    private const DISABLED_KEY = 'places-api-disabled';

    // @return array{community:?string, subdistrict:?string, district:?string, province:?string, road:?string}|null
    public function area(float $latitude, float $longitude): ?array
    {
        $cacheKey = sprintf('place-area:%.3f,%.3f', $latitude, $longitude);

        $cached = Cache::get($cacheKey);

        if (is_array($cached)) {
            return $cached['area'];
        }

        // ทั้ง Server เรียกได้ไม่เกิน 1 ครั้ง/วินาที (เกิน → แอปใช้ที่อยู่จากมือถือแทน)
        if (RateLimiter::tooManyAttempts('nominatim', 1)) {
            return null;
        }

        RateLimiter::hit('nominatim', 1);

        try {
            $response = Http::timeout(6)
                ->withHeaders(['User-Agent' => $this->userAgent()])
                ->get(self::NOMINATIM, [
                    'format' => 'jsonv2',
                    'lat' => $latitude,
                    'lon' => $longitude,
                    'zoom' => 17,
                    'addressdetails' => 1,
                    'accept-language' => 'th',
                ]);
        } catch (Throwable $e) {
            Log::warning('Nominatim failed', ['error' => $e->getMessage()]);

            return null;
        }

        if ($response->failed()) {
            Log::warning('Nominatim failed', ['status' => $response->status()]);

            return null;
        }

        // กลางทะเล / ไม่มีข้อมูล → ได้ {"error": ...}
        $address = $response->json('address');

        $area = is_array($address) ? self::parseArea($address) : null;

        Cache::put($cacheKey, ['area' => $area], now()->addDays(7));

        return $area;
    }

    // แปลงที่อยู่ของ OpenStreetMap ให้เป็นแบบไทย
    // แต่ละพื้นที่ใส่ข้อมูลไว้คนละช่อง จึงดูจากคำนำหน้าด้วย
    // เช่น ตำบล/แขวง อาจอยู่ใน city_district, quarter หรือ suburb
    public static function parseArea(array $address): ?array
    {
        $pick = function (array $keys, array $prefixes = [], array $except = []) use ($address): ?string {
            foreach ($keys as $key) {
                $value = trim((string) ($address[$key] ?? ''));

                if ($value === '') {
                    continue;
                }

                if ($prefixes !== [] && !Str::startsWith($value, $prefixes)) {
                    continue;
                }

                if ($except !== [] && Str::startsWith($value, $except)) {
                    continue;
                }

                return $value;
            }

            return null;
        };

        $adminPrefixes = ['ตำบล', 'แขวง', 'อำเภอ', 'เขต', 'เทศบาล', 'จังหวัด'];

        $area = [
            // หมู่บ้าน / ชุมชน / หมู่ที่
            'community' => $pick(['hamlet', 'village', 'neighbourhood', 'residential'], [], $adminPrefixes)
                ?? $pick(['suburb', 'quarter'], ['หมู่', 'บ้าน', 'ชุมชน']),
            'subdistrict' => $pick(['city_district', 'quarter', 'suburb', 'town', 'village', 'municipality'], ['ตำบล', 'แขวง']),
            'district' => $pick(['county', 'suburb', 'city_district', 'state_district'], ['อำเภอ', 'เขต']),
            'province' => $pick(['province', 'state']) ?? $pick(['city'], ['กรุงเทพ']),
            'road' => $pick(['road']),
        ];

        return array_filter($area) === [] ? null : $area;
    }

    public function placesEnabled(): bool
    {
        return filled(config('services.google.maps_server_key'))
            && !Cache::has(self::DISABLED_KEY);
    }

    // @return list<array{name:string, type:?string, distance_meters:int, tourist:bool}>|null
    //         null = ยังไม่ได้เปิด Places API / เรียกไม่สำเร็จ
    public function nearby(float $latitude, float $longitude): ?array
    {
        if (!$this->placesEnabled()) {
            return null;
        }

        try {
            $response = Http::timeout(8)
                ->withHeaders([
                    'X-Goog-Api-Key' => config('services.google.maps_server_key'),
                    'X-Goog-FieldMask' => 'places.displayName,places.primaryTypeDisplayName,places.types,places.location',
                ])
                ->post(self::NEARBY, [
                    'maxResultCount' => 10,
                    'rankPreference' => 'DISTANCE',
                    'languageCode' => 'th',
                    'regionCode' => 'TH',
                    'locationRestriction' => [
                        'circle' => [
                            'center' => ['latitude' => $latitude, 'longitude' => $longitude],
                            'radius' => self::NEARBY_RADIUS,
                        ],
                    ],
                ]);
        } catch (Throwable $e) {
            Log::warning('Places API failed', ['error' => $e->getMessage()]);

            return null;
        }

        if ($response->failed()) {
            // ยังไม่ได้เปิด Places API หรือ key ไม่อนุญาต → พัก 10 นาที
            if (in_array($response->status(), [401, 403], true)) {
                Cache::put(self::DISABLED_KEY, true, now()->addMinutes(10));
            }

            Log::warning('Places API failed', [
                'status' => $response->status(),
                'error' => $response->json('error.message'),
            ]);

            return null;
        }

        $places = [];

        foreach ((array) $response->json('places', []) as $place) {
            $name = trim((string) ($place['displayName']['text'] ?? ''));

            $lat = $place['location']['latitude'] ?? null;
            $lng = $place['location']['longitude'] ?? null;

            if ($name === '' || !is_numeric($lat) || !is_numeric($lng)) {
                continue;
            }

            $type = trim((string) ($place['primaryTypeDisplayName']['text'] ?? ''));

            $places[] = [
                'name' => $name,
                'type' => $type === '' ? null : $type,
                'distance_meters' => (int) round(self::distance($latitude, $longitude, (float) $lat, (float) $lng)),
                'tourist' => array_intersect((array) ($place['types'] ?? []), self::TOURIST_TYPES) !== [],
            ];
        }

        usort($places, fn (array $a, array $b) => $a['distance_meters'] <=> $b['distance_meters']);

        return array_slice($places, 0, self::NEARBY_LIMIT);
    }

    // ระยะทางเส้นตรง (เมตร)
    public static function distance(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earth = 6371000;

        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);

        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return $earth * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }

    // Nominatim ต้องรู้ว่าแอปไหนเรียก
    private function userAgent(): string
    {
        $contact = config('legal.support_email') ?: config('app.url');

        return 'Oravelle/1.0 (' . $contact . ')';
    }
}
