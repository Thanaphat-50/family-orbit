<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

// =======================================================
// เส้นทางตามถนนจริง (Google Routes API: computeRoutes)
//
// - ใช้แบบพื้นฐาน (ไม่คิดสภาพจราจร) → อยู่ใน SKU Essentials ที่มีโควตาฟรีต่อเดือน
// - เก็บผลไว้ 10 นาที ตามพิกัดที่ปัดแล้ว (~11 เมตร) → เปิดดูซ้ำไม่เสียโควตา
// =======================================================

class RouteFinder
{
    private const ENDPOINT = 'https://routes.googleapis.com/directions/v2:computeRoutes';

    // โหมดในแอป → travelMode ของ Google
    public const MODES = [
        'drive' => 'DRIVE',
        'motorcycle' => 'TWO_WHEELER',
        'walk' => 'WALK',
    ];

    public function enabled(): bool
    {
        return filled(config('services.google.maps_server_key'));
    }

    // @return array{distance_meters:int, duration_seconds:int, polyline:string}|null
    //         null = หาเส้นทางไม่ได้ (เช่น อยู่คนละเกาะ)
    // @throws RuntimeException เรียก Google ไม่สำเร็จ
    public function route(
        float $fromLat,
        float $fromLng,
        float $toLat,
        float $toLng,
        string $mode
    ): ?array {
        $points = array_map(
            fn (float $value) => number_format($value, 4, '.', ''),
            [$fromLat, $fromLng, $toLat, $toLng]
        );

        $cacheKey = 'route:' . $mode . ':' . implode(',', $points);

        $cached = Cache::get($cacheKey);

        if (is_array($cached)) {
            return $cached['route'];
        }

        $route = $this->request($fromLat, $fromLng, $toLat, $toLng, $mode);

        Cache::put($cacheKey, ['route' => $route], now()->addMinutes(10));

        return $route;
    }

    private function request(
        float $fromLat,
        float $fromLng,
        float $toLat,
        float $toLng,
        string $mode
    ): ?array {
        $body = [
            'origin' => $this->waypoint($fromLat, $fromLng),
            'destination' => $this->waypoint($toLat, $toLng),
            'travelMode' => self::MODES[$mode],
            'languageCode' => 'th',
            'units' => 'METRIC',
        ];

        // เดินเท้าตั้ง routingPreference ไม่ได้ (Google ตอบ error)
        if ($mode !== 'walk') {
            $body['routingPreference'] = 'TRAFFIC_UNAWARE';
        }

        $response = Http::timeout(10)
            ->withHeaders([
                'X-Goog-Api-Key' => config('services.google.maps_server_key'),
                'X-Goog-FieldMask' => 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
            ])
            ->post(self::ENDPOINT, $body);

        if ($response->failed()) {
            Log::warning('Routes API failed', [
                'status' => $response->status(),
                'error' => $response->json('error.message'),
            ]);

            throw new RuntimeException('Routes API failed');
        }

        $route = $response->json('routes.0');

        if (!is_array($route)) {
            return null;
        }

        return [
            'distance_meters' => (int) ($route['distanceMeters'] ?? 0),
            // Google ส่งเวลาเป็นข้อความ เช่น "754s"
            'duration_seconds' => (int) rtrim((string) ($route['duration'] ?? '0s'), 's'),
            'polyline' => (string) ($route['polyline']['encodedPolyline'] ?? ''),
        ];
    }

    private function waypoint(float $latitude, float $longitude): array
    {
        return [
            'location' => [
                'latLng' => [
                    'latitude' => $latitude,
                    'longitude' => $longitude,
                ],
            ],
        ];
    }
}
