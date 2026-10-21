<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\DeviceToken;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PushNotificationTest extends TestCase
{
    use RefreshDatabase;

    private const FCM_URL = 'https://fcm.googleapis.com/v1/projects/test-project/messages:send';

    protected function setUp(): void
    {
        parent::setUp();

        // ส่งแจ้งเตือนเด้งทันที (ปกติส่งหลังตอบแอปไปแล้ว)
        $this->withoutDefer();

        // ห้ามยิงไป Firebase จริงระหว่าง Test
        Http::preventStrayRequests();
    }

    // ตั้งค่า Service account ปลอม + access token ใน cache (ไม่ต้องเซ็นจริง)
    private function configureFcm(string $privateKey = 'unused-in-this-test'): void
    {
        config(['services.fcm.credentials' => base64_encode(json_encode([
            'type' => 'service_account',
            'project_id' => 'test-project',
            'client_email' => 'push@test-project.iam.gserviceaccount.com',
            'private_key' => $privateKey,
        ]))]);

        Cache::put('fcm.access_token.test-project', 'cached-access-token', 600);
    }

    private function notify(User $user, string $type = 'new_post'): ?AppNotification
    {
        $notification = AppNotification::create([
            'user_id' => $user->id,
            'type' => $type,
            'title' => 'โพสต์ใหม่',
            'message' => 'แม่ สร้างโพสต์ใหม่',
            'data' => ['post_id' => 42],
            'is_read' => false,
        ]);

        return $notification->exists ? $notification : null;
    }

    // เครื่องที่ล็อกอินอยู่ (ผูกกับ Token ของแอปจริง)
    private function device(User $user, string $token): DeviceToken
    {
        return DeviceToken::create([
            'user_id' => $user->id,
            'access_token_id' => $user->createToken('app')->accessToken->id,
            'token' => $token,
        ]);
    }

    // =====================================================
    // Token ของมือถือ
    // =====================================================

    public function test_device_token_is_registered_and_moves_to_new_account(): void
    {
        $first = User::factory()->create();
        $second = User::factory()->create();

        $firstLogin = $first->createToken('app');

        $this->withToken($firstLogin->plainTextToken)
            ->postJson('/api/device-tokens', ['token' => 'phone-token-1'])
            ->assertOk();

        $this->withToken($firstLogin->plainTextToken)
            ->postJson('/api/device-tokens', ['token' => 'phone-token-1'])
            ->assertOk();

        $this->assertSame(1, DeviceToken::count());
        $this->assertSame($first->id, DeviceToken::first()->user_id);
        $this->assertSame($firstLogin->accessToken->id, DeviceToken::first()->access_token_id);

        // เครื่องเดิมล็อกอินบัญชีอื่น → รหัสเครื่องเป็นของบัญชีใหม่
        $this->app['auth']->forgetGuards();

        $secondLogin = $second->createToken('app');

        $this->withToken($secondLogin->plainTextToken)
            ->postJson('/api/device-tokens', ['token' => 'phone-token-1'])
            ->assertOk();

        $this->assertSame(1, DeviceToken::count());
        $this->assertSame($second->id, DeviceToken::first()->user_id);
        $this->assertSame($secondLogin->accessToken->id, DeviceToken::first()->access_token_id);
    }

    // ออกจากระบบ → Token ของแอปถูกลบ → เครื่องนี้ไม่รับแจ้งเตือนอีก
    public function test_logout_removes_the_device(): void
    {
        $user = User::factory()->create();

        $login = $user->createToken('app');

        $this->withToken($login->plainTextToken)
            ->postJson('/api/device-tokens', ['token' => 'phone-a'])
            ->assertOk();

        $this->withToken($login->plainTextToken)
            ->postJson('/api/logout')
            ->assertOk();

        $this->assertSame(0, DeviceToken::count());
    }

    public function test_only_latest_devices_are_kept(): void
    {
        $user = User::factory()->create();

        for ($i = 1; $i <= DeviceToken::MAX_PER_USER + 2; $i++) {
            DeviceToken::create([
                'user_id' => $user->id,
                'token' => 'old-' . $i,
                'last_used_at' => now()->subDays(30 - $i),
            ]);
        }

        $this->withToken($user->createToken('app')->plainTextToken)
            ->postJson('/api/device-tokens', ['token' => 'newest'])
            ->assertOk();

        $tokens = $user->deviceTokens()->pluck('token');

        $this->assertCount(DeviceToken::MAX_PER_USER, $tokens);
        $this->assertContains('newest', $tokens);
        $this->assertNotContains('old-1', $tokens);
    }

    public function test_device_token_requires_login_and_token(): void
    {
        $this->postJson('/api/device-tokens', ['token' => 'x'])->assertUnauthorized();

        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/device-tokens', [])->assertStatus(422);
    }

    // =====================================================
    // ส่งแจ้งเตือนเด้ง
    // =====================================================

    public function test_new_notification_is_pushed_to_every_device(): void
    {
        $this->configureFcm();

        Http::fake([self::FCM_URL => Http::response(['name' => 'projects/test-project/messages/1'])]);

        $user = User::factory()->create();

        $this->device($user, 'phone-a');
        $this->device($user, 'tablet-b');

        $notification = $this->notify($user);

        Http::assertSentCount(2);

        Http::assertSent(function (Request $request) use ($notification) {
            $message = $request['message'];

            return $request->url() === self::FCM_URL
                && $request->hasHeader('Authorization', 'Bearer cached-access-token')
                && $message['fid'] === 'phone-a'
                && $message['notification']['title'] === 'โพสต์ใหม่'
                && $message['notification']['body'] === 'แม่ สร้างโพสต์ใหม่'
                && $message['data'] === [
                    'type' => 'new_post',
                    'notification_id' => (string) $notification->id,
                    'post_id' => '42',
                ]
                && $message['android']['notification']['channel_id'] === 'klaikan_default';
        });
    }

    public function test_disabled_notification_type_is_not_pushed(): void
    {
        $this->configureFcm();

        Http::fake();

        $user = User::factory()->create();
        $user->notification_settings = ['new_post' => false];
        $user->save();

        $this->device($user, 'phone-a');

        $this->assertNull($this->notify($user, 'new_post'));

        Http::assertNothingSent();
    }

    public function test_logged_out_or_expired_devices_get_no_push(): void
    {
        $this->configureFcm();

        Http::fake();

        $user = User::factory()->create();

        // ไม่ได้ผูกกับการล็อกอิน
        DeviceToken::create(['user_id' => $user->id, 'token' => 'no-login']);

        // ล็อกอินนานเกินอายุ Token ของแอป
        $expired = $this->device($user, 'expired-login');

        $expired->accessToken
            ->forceFill(['created_at' => now()->subMinutes(config('sanctum.expiration') + 1)])
            ->save();

        $this->assertNotNull($this->notify($user));

        Http::assertNothingSent();
    }

    public function test_nothing_is_sent_without_firebase_credentials(): void
    {
        config([
            'services.fcm.credentials' => null,
            'services.fcm.credentials_path' => null,
        ]);

        Http::fake();

        $user = User::factory()->create();

        $this->device($user, 'phone-a');

        $this->assertNotNull($this->notify($user));

        Http::assertNothingSent();
    }

    public function test_uninstalled_device_token_is_removed(): void
    {
        $this->configureFcm();

        Http::fake([self::FCM_URL => Http::response([
            'error' => [
                'code' => 404,
                'status' => 'NOT_FOUND',
                'details' => [[
                    '@type' => 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
                    'errorCode' => 'UNREGISTERED',
                ]],
            ],
        ], 404)]);

        $user = User::factory()->create();

        $this->device($user, 'uninstalled-phone');

        $this->assertNotNull($this->notify($user));

        $this->assertSame(0, DeviceToken::count());
    }

    public function test_failed_push_does_not_break_the_request(): void
    {
        $this->configureFcm();

        Http::fake([self::FCM_URL => Http::response(['error' => ['status' => 'UNAVAILABLE']], 503)]);

        $user = User::factory()->create();

        $this->device($user, 'phone-a');

        $this->assertNotNull($this->notify($user));

        // Server ของ Firebase มีปัญหาชั่วคราว → ไม่ลบ token
        $this->assertSame(1, DeviceToken::count());
    }

    // ขอ access token ด้วย JWT ที่เซ็นด้วยกุญแจของ Service account
    public function test_access_token_is_requested_with_signed_jwt(): void
    {
        $key = openssl_pkey_new([
            'private_key_bits' => 2048,
            'private_key_type' => OPENSSL_KEYTYPE_RSA,
        ]);

        if ($key === false) {
            $this->markTestSkipped('OpenSSL cannot generate keys here (set OPENSSL_CONF to run this test).');
        }

        openssl_pkey_export($key, $privateKey);

        $publicKey = openssl_pkey_get_details($key)['key'];

        $this->configureFcm($privateKey);

        Cache::forget('fcm.access_token.test-project');

        Http::fake([
            'https://oauth2.googleapis.com/token' => Http::response([
                'access_token' => 'fresh-access-token',
                'expires_in' => 3599,
            ]),
            self::FCM_URL => Http::response(['name' => 'ok']),
        ]);

        $user = User::factory()->create();

        $this->device($user, 'phone-a');

        $this->notify($user);

        Http::assertSent(function (Request $request) use ($publicKey) {
            if ($request->url() !== 'https://oauth2.googleapis.com/token') {
                return false;
            }

            [$header, $claims, $signature] = explode('.', $request['assertion']);

            $decode = fn (string $part) => base64_decode(strtr($part, '-_', '+/'));

            $payload = json_decode($decode($claims), true);

            return $request['grant_type'] === 'urn:ietf:params:oauth:grant-type:jwt-bearer'
                && json_decode($decode($header), true)['alg'] === 'RS256'
                && $payload['iss'] === 'push@test-project.iam.gserviceaccount.com'
                && $payload['scope'] === 'https://www.googleapis.com/auth/firebase.messaging'
                && openssl_verify("{$header}.{$claims}", $decode($signature), $publicKey, OPENSSL_ALGO_SHA256) === 1;
        });

        Http::assertSent(fn (Request $request) => $request->url() === self::FCM_URL
            && $request->hasHeader('Authorization', 'Bearer fresh-access-token'));

        // ใช้ access token ซ้ำในการแจ้งเตือนครั้งถัดไป
        $this->notify($user);

        Http::assertSentCount(3);
    }

    public function test_deleting_account_removes_device_tokens(): void
    {
        $user = User::factory()->create();

        $this->device($user, 'phone-a');

        $user->delete();

        $this->assertSame(0, DeviceToken::count());
    }
}
