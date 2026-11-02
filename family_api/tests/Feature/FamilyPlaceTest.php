<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\UserLocation;
use App\Services\PlaceFinder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class FamilyPlaceTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/*';

    private const PLACES_URL = 'https://places.googleapis.com/*';

    // คำตอบจริงของ Nominatim (อนุสาวรีย์ประชาธิปไตย)
    private const BANGKOK_ADDRESS = [
        'road' => 'วงเวียนอนุสาวรีย์ประชาธิปไตย',
        'neighbourhood' => 'ชุมชนหลังวัดราชนัดดา',
        'quarter' => 'แขวงบวรนิเวศ',
        'suburb' => 'เขตพระนคร',
        'city' => 'กรุงเทพมหานคร',
        'postcode' => '10200',
        'country' => 'ประเทศไทย',
    ];

    protected function setUp(): void
    {
        parent::setUp();

        // ห้ามยิงไป OpenStreetMap / Google จริงระหว่าง Test
        Http::preventStrayRequests();

        config(['services.google.maps_server_key' => 'server-key']);
    }

    private function family(bool $sharing = true): array
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $this->createFamily($mom, [$dad]);

        $dad->location_sharing = $sharing;
        $dad->save();

        UserLocation::create([
            'user_id' => $dad->id,
            'latitude' => 13.7563,
            'longitude' => 100.5018,
            'last_seen_at' => now(),
        ]);

        return [$mom, $dad];
    }

    private function fakeServices(int $placesStatus = 200): void
    {
        Http::fake([
            self::NOMINATIM_URL => Http::response(['address' => self::BANGKOK_ADDRESS]),
            self::PLACES_URL => $placesStatus === 200
                ? Http::response(['places' => [
                    [
                        'displayName' => ['text' => 'ร้านกาแฟหัวมุม'],
                        'primaryTypeDisplayName' => ['text' => 'ร้านกาแฟ'],
                        'types' => ['cafe', 'food'],
                        'location' => ['latitude' => 13.7570, 'longitude' => 100.5018],
                    ],
                    [
                        'displayName' => ['text' => 'อนุสาวรีย์ประชาธิปไตย'],
                        'primaryTypeDisplayName' => ['text' => 'สถานที่ท่องเที่ยว'],
                        'types' => ['tourist_attraction', 'point_of_interest'],
                        'location' => ['latitude' => 13.7564, 'longitude' => 100.5019],
                    ],
                    // ไม่มีชื่อ → ข้าม
                    [
                        'displayName' => ['text' => ''],
                        'location' => ['latitude' => 13.7563, 'longitude' => 100.5018],
                    ],
                ]])
                : Http::response(['error' => ['message' => 'Places API (New) has not been used in project']], $placesStatus),
        ]);
    }

    public function test_returns_community_area_and_nearby_places(): void
    {
        [$mom, $dad] = $this->family();

        $this->fakeServices();

        Sanctum::actingAs($mom);

        $this->getJson("/api/family/members/{$dad->id}/place")
            ->assertOk()
            ->assertJsonPath('area.community', 'ชุมชนหลังวัดราชนัดดา')
            ->assertJsonPath('area.subdistrict', 'แขวงบวรนิเวศ')
            ->assertJsonPath('area.district', 'เขตพระนคร')
            ->assertJsonPath('area.province', 'กรุงเทพมหานคร')
            ->assertJsonCount(2, 'places')
            // เรียงจากใกล้สุด
            ->assertJsonPath('places.0.name', 'อนุสาวรีย์ประชาธิปไตย')
            ->assertJsonPath('places.0.type', 'สถานที่ท่องเที่ยว')
            ->assertJsonPath('places.0.tourist', true)
            ->assertJsonPath('places.1.tourist', false)
            ->assertJsonPath('places.1.distance_meters', 78);

        Http::assertSent(fn (Request $request) => str_starts_with($request->url(), 'https://nominatim.openstreetmap.org/reverse')
            && $request['accept-language'] === 'th'
            && str_starts_with($request->header('User-Agent')[0] ?? '', 'Oravelle/'));

        Http::assertSent(fn (Request $request) => str_starts_with($request->url(), 'https://places.googleapis.com/')
            && $request->hasHeader('X-Goog-Api-Key', 'server-key')
            && $request['rankPreference'] === 'DISTANCE'
            && $request['languageCode'] === 'th');
    }

    public function test_area_is_cached_but_places_are_not(): void
    {
        [$mom, $dad] = $this->family();

        $this->fakeServices();

        Sanctum::actingAs($mom);

        $this->getJson("/api/family/members/{$dad->id}/place")->assertOk();

        $this->travel(2)->seconds();

        $this->getJson("/api/family/members/{$dad->id}/place")
            ->assertOk()
            ->assertJsonPath('area.community', 'ชุมชนหลังวัดราชนัดดา');

        $nominatimCalls = Http::recorded(fn (Request $request) => str_contains($request->url(), 'nominatim'))->count();
        $placesCalls = Http::recorded(fn (Request $request) => str_contains($request->url(), 'places.googleapis'))->count();

        $this->assertSame(1, $nominatimCalls);
        $this->assertSame(2, $placesCalls);
    }

    public function test_places_api_not_enabled_still_returns_area_and_pauses_calls(): void
    {
        [$mom, $dad] = $this->family();

        $this->fakeServices(403);

        Sanctum::actingAs($mom);

        $this->getJson("/api/family/members/{$dad->id}/place")
            ->assertOk()
            ->assertJsonPath('places', null)
            ->assertJsonPath('area.district', 'เขตพระนคร');

        $this->getJson("/api/family/members/{$dad->id}/place")->assertOk();

        // ครั้งที่ 2 ไม่เรียก Google ซ้ำ
        $this->assertSame(1, Http::recorded(fn (Request $request) => str_contains($request->url(), 'places.googleapis'))->count());
    }

    public function test_without_server_key_only_area_is_returned(): void
    {
        config(['services.google.maps_server_key' => null]);

        [$mom, $dad] = $this->family();

        $this->fakeServices();

        Sanctum::actingAs($mom);

        $this->getJson("/api/family/members/{$dad->id}/place")
            ->assertOk()
            ->assertJsonPath('places', null)
            ->assertJsonPath('area.community', 'ชุมชนหลังวัดราชนัดดา');

        Http::assertNotSent(fn (Request $request) => str_contains($request->url(), 'places.googleapis'));
    }

    public function test_only_same_family_with_sharing_on(): void
    {
        [$mom, $dad] = $this->family(sharing: false);

        $outsider = User::factory()->create();
        $this->createFamily($outsider);

        Http::fake();

        Sanctum::actingAs($mom);
        $this->getJson("/api/family/members/{$dad->id}/place")->assertNotFound();

        $dad->location_sharing = true;
        $dad->save();

        Sanctum::actingAs($outsider);
        $this->getJson("/api/family/members/{$dad->id}/place")->assertNotFound();

        Http::assertNothingSent();
    }

    public function test_parses_thai_areas_from_openstreetmap(): void
    {
        // ขอนแก่น: ชื่อหมู่บ้านอยู่ใน neighbourhood, ตำบลอยู่ใน city_district
        $this->assertSame([
            'community' => 'บ้านศูนย์แพทย์ 1',
            'subdistrict' => 'ตำบลในเมือง',
            'district' => 'อำเภอเมืองขอนแก่น',
            'province' => 'จังหวัดขอนแก่น',
            'road' => 'ถนนแก่นร่มเกล้า',
        ], PlaceFinder::parseArea([
            'road' => 'ถนนแก่นร่มเกล้า',
            'neighbourhood' => 'บ้านศูนย์แพทย์ 1',
            'city_district' => 'ตำบลในเมือง',
            'city' => 'เทศบาลนครขอนแก่น',
            'municipality' => 'ศิลา',
            'county' => 'อำเภอเมืองขอนแก่น',
            'province' => 'จังหวัดขอนแก่น',
        ]));

        // อยุธยา: หมู่ที่ อยู่ใน suburb
        $ayutthaya = PlaceFinder::parseArea([
            'road' => 'ถนนศรีสรรเพชญ์',
            'suburb' => 'หมู่ที่ 2',
            'city_district' => 'ตำบลประตูชัย',
            'county' => 'อำเภอพระนครศรีอยุธยา',
            'province' => 'จังหวัดพระนครศรีอยุธยา',
        ]);

        $this->assertSame('หมู่ที่ 2', $ayutthaya['community']);
        $this->assertSame('ตำบลประตูชัย', $ayutthaya['subdistrict']);

        // เชียงใหม่: แขวงของเทศบาลไม่ใช่ชื่อหมู่บ้าน
        $chiangMai = PlaceFinder::parseArea([
            'suburb' => 'แขวงศรีวิชัย',
            'city_district' => 'ตำบลพระสิงห์',
            'county' => 'อำเภอเมืองเชียงใหม่',
            'province' => 'จังหวัดเชียงใหม่',
        ]);

        $this->assertNull($chiangMai['community']);
        $this->assertSame('ตำบลพระสิงห์', $chiangMai['subdistrict']);

        $this->assertNull(PlaceFinder::parseArea(['country' => 'ประเทศไทย']));
    }
}
