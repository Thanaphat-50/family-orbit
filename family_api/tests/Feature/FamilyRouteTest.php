<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\UserLocation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class FamilyRouteTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    private const ROUTES_URL = 'https://routes.googleapis.com/*';

    protected function setUp(): void
    {
        parent::setUp();

        // ห้ามยิงไป Google จริงระหว่าง Test
        Http::preventStrayRequests();

        config(['services.google.maps_server_key' => 'server-key']);
    }

    private function fakeRoute(): void
    {
        Http::fake([self::ROUTES_URL => Http::response([
            'routes' => [[
                'distanceMeters' => 2140,
                'duration' => '420s',
                'polyline' => ['encodedPolyline' => '_p~iF~ps|U_ulLnnqC'],
            ]],
        ])]);
    }

    private function family(): array
    {
        $mom = User::factory()->create();
        $dad = User::factory()->create();

        $this->createFamily($mom, [$dad]);

        UserLocation::create([
            'user_id' => $dad->id,
            'latitude' => 13.7745,
            'longitude' => 100.515,
            'last_seen_at' => now(),
        ]);

        return [$mom, $dad];
    }

    private function url(User $member, string $query = ''): string
    {
        return "/api/family/members/{$member->id}/route?from_lat=13.7563&from_lng=100.5018" . $query;
    }

    public function test_returns_road_distance_time_and_line(): void
    {
        [$mom, $dad] = $this->family();

        $this->fakeRoute();

        Sanctum::actingAs($mom);

        $this->getJson($this->url($dad))
            ->assertOk()
            ->assertJsonPath('mode', 'drive')
            ->assertJsonPath('distance_meters', 2140)
            ->assertJsonPath('duration_seconds', 420)
            ->assertJsonPath('polyline', '_p~iF~ps|U_ulLnnqC');

        Http::assertSent(fn (Request $request) => $request->hasHeader('X-Goog-Api-Key', 'server-key')
            && $request['travelMode'] === 'DRIVE'
            && $request['routingPreference'] === 'TRAFFIC_UNAWARE'
            && $request['destination']['location']['latLng']['latitude'] == 13.7745);

        // เปิดดูซ้ำ → ใช้ผลเดิม ไม่เรียก Google อีก
        $this->getJson($this->url($dad))->assertOk();

        Http::assertSentCount(1);
    }

    public function test_walking_and_motorcycle_modes(): void
    {
        [$mom, $dad] = $this->family();

        $this->fakeRoute();

        Sanctum::actingAs($mom);

        $this->getJson($this->url($dad, '&mode=walk'))->assertOk()->assertJsonPath('mode', 'walk');

        // เดินเท้าตั้ง routingPreference ไม่ได้
        Http::assertSent(fn (Request $request) => $request['travelMode'] === 'WALK'
            && !isset($request['routingPreference']));

        $this->getJson($this->url($dad, '&mode=motorcycle'))->assertOk();

        Http::assertSent(fn (Request $request) => $request['travelMode'] === 'TWO_WHEELER');

        $this->getJson($this->url($dad, '&mode=boat'))->assertStatus(422);
    }

    public function test_without_server_key_the_app_uses_straight_distance(): void
    {
        [$mom, $dad] = $this->family();

        config(['services.google.maps_server_key' => null]);

        Sanctum::actingAs($mom);

        $this->getJson($this->url($dad))
            ->assertStatus(409)
            ->assertJsonPath('code', 'routes_disabled');
    }

    public function test_cannot_route_to_someone_outside_the_family(): void
    {
        [$mom, $dad] = $this->family();

        $this->fakeRoute();

        Sanctum::actingAs(User::factory()->create());

        $this->getJson($this->url($dad))->assertNotFound();

        Http::assertNothingSent();
    }

    public function test_member_who_stopped_sharing_has_no_route(): void
    {
        [$mom, $dad] = $this->family();

        $dad->forceFill(['location_sharing' => false])->save();

        $this->fakeRoute();

        Sanctum::actingAs($mom);

        $this->getJson($this->url($dad))->assertNotFound();

        Http::assertNothingSent();
    }

    public function test_no_route_and_google_errors(): void
    {
        [$mom, $dad] = $this->family();

        Http::fake([self::ROUTES_URL => Http::sequence()
            ->push(['routes' => []])
            ->push(['error' => ['message' => 'API key not valid']], 400)]);

        Sanctum::actingAs($mom);

        $this->getJson($this->url($dad))
            ->assertNotFound()
            ->assertJsonPath('code', 'no_route');

        $this->getJson($this->url($dad, '&mode=walk'))
            ->assertStatus(424)
            ->assertJsonPath('code', 'route_failed');
    }
}
