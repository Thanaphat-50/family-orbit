<?php

namespace Tests\Feature;

use App\Models\SocialAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SocialLoginTest extends TestCase
{
    use RefreshDatabase;

    private const GOOGLE_URL = 'https://oauth2.googleapis.com/tokeninfo*';
    private const LINE_URL = 'https://api.line.me/oauth2/v2.1/verify';

    protected function setUp(): void
    {
        parent::setUp();

        // ห้ามยิงไปผู้ให้บริการจริงระหว่าง Test
        Http::preventStrayRequests();

        config([
            'services.google.client_ids' => 'web-client.apps.googleusercontent.com',
            'services.line.channel_id' => '1650000000',
            'services.facebook.app_id' => 'fb-app',
            'services.facebook.app_secret' => 'fb-secret',
            'services.facebook.graph_version' => null,
        ]);
    }

    private function fakeGoogle(array $overrides = []): void
    {
        Http::fake([self::GOOGLE_URL => Http::response(array_merge([
            'iss' => 'https://accounts.google.com',
            'aud' => 'web-client.apps.googleusercontent.com',
            'sub' => 'google-123',
            'email' => 'mom@gmail.com',
            'email_verified' => 'true',
            'name' => 'Mom Google',
            'exp' => (string) (time() + 600),
        ], $overrides))]);
    }

    private function fakeLine(array $overrides = []): void
    {
        Http::fake([self::LINE_URL => Http::response(array_merge([
            'iss' => 'https://access.line.me',
            'aud' => '1650000000',
            'sub' => 'U-line-1',
            'name' => 'ป้าแดง',
            'email' => 'daeng@example.com',
        ], $overrides))]);
    }

    // =====================================================
    // ปุ่มที่แสดงในแอป
    // =====================================================

    public function test_providers_lists_only_configured_logins(): void
    {
        config(['services.facebook.app_secret' => null]);

        $this->getJson('/api/auth/providers')
            ->assertOk()
            ->assertJsonPath('providers.google.server_client_id', 'web-client.apps.googleusercontent.com')
            ->assertJsonPath('providers.line.channel_id', '1650000000')
            ->assertJsonPath('providers.facebook', null);
    }

    public function test_facebook_config_points_back_to_our_callback(): void
    {
        $url = $this->getJson('/api/auth/providers')
            ->assertOk()
            ->json('providers.facebook.auth_url');

        $this->assertStringStartsWith('https://www.facebook.com/dialog/oauth?', $url);
        $this->assertStringContainsString(urlencode(route('auth.facebook.callback')), $url);
        $this->assertStringContainsString('client_id=fb-app', $url);
    }

    // =====================================================
    // Google
    // =====================================================

    public function test_google_creates_an_account_then_signs_in_again(): void
    {
        $this->fakeGoogle();

        $first = $this->postJson('/api/auth/social/google', ['id_token' => 'google-token'])
            ->assertCreated()
            ->assertJsonPath('created', true)
            ->assertJsonPath('user.email', 'mom@gmail.com');

        $this->assertNotEmpty($first->json('token'));

        $user = User::firstWhere('email', 'mom@gmail.com');

        $this->assertSame('Mom Google', $user->name);
        $this->assertFalse($user->hasPassword());
        $this->assertNotNull($user->email_verified_at);

        $this->postJson('/api/auth/social/google', ['id_token' => 'google-token'])
            ->assertOk()
            ->assertJsonPath('created', false)
            ->assertJsonPath('user.id', $user->id);

        $this->assertSame(1, User::count());

        Http::assertSent(fn (Request $request) => $request['id_token'] === 'google-token');
    }

    public function test_google_with_verified_email_joins_the_existing_account(): void
    {
        $existing = User::factory()->create(['email' => 'mom@gmail.com']);

        $this->fakeGoogle();

        $this->postJson('/api/auth/social/google', ['id_token' => 'google-token'])
            ->assertOk()
            ->assertJsonPath('user.id', $existing->id);

        $this->assertTrue($existing->socialAccounts()->where('provider', 'google')->exists());
        $this->assertTrue($existing->fresh()->hasPassword());
    }

    public function test_google_token_for_another_app_is_rejected(): void
    {
        $this->fakeGoogle(['aud' => 'someone-else.apps.googleusercontent.com']);

        $this->postJson('/api/auth/social/google', ['id_token' => 'google-token'])
            ->assertStatus(422);

        $this->assertSame(0, User::count());
    }

    public function test_expired_google_token_is_rejected(): void
    {
        Http::fake([self::GOOGLE_URL => Http::response(['error' => 'invalid_token'], 400)]);

        $this->postJson('/api/auth/social/google', ['id_token' => 'old-token'])
            ->assertStatus(422);
    }

    public function test_login_that_is_not_configured_is_rejected(): void
    {
        config(['services.line.channel_id' => null]);

        $this->postJson('/api/auth/social/line', ['id_token' => 'x'])
            ->assertStatus(422);

        $this->postJson('/api/auth/social/twitter', ['id_token' => 'x'])
            ->assertNotFound();
    }

    // =====================================================
    // LINE
    // =====================================================

    public function test_line_creates_an_account(): void
    {
        $this->fakeLine(['email' => null]);

        $this->postJson('/api/auth/social/line', ['id_token' => 'line-token'])
            ->assertCreated()
            ->assertJsonPath('user.name', 'ป้าแดง')
            ->assertJsonPath('user.email', null);

        Http::assertSent(fn (Request $request) => $request['id_token'] === 'line-token'
            && $request['client_id'] === '1650000000');
    }

    // อีเมลจาก LINE ไม่ได้ยืนยัน → ไม่ผูกกับบัญชีเดิมเอง (กันสวมรอย)
    public function test_line_does_not_take_over_an_existing_email(): void
    {
        $existing = User::factory()->create(['email' => 'daeng@example.com']);

        $this->fakeLine();

        $this->postJson('/api/auth/social/line', ['id_token' => 'line-token'])
            ->assertStatus(409)
            ->assertJsonPath('code', 'email_in_use')
            ->assertJsonPath('email', 'daeng@example.com')
            ->assertJsonPath('sign_in_with.password', true)
            ->assertJsonPath('sign_in_with.providers', []);

        $this->assertSame(0, SocialAccount::count());
        $this->assertSame(1, User::count());
        $this->assertSame($existing->id, User::first()->id);
    }

    // =====================================================
    // Facebook
    // =====================================================

    public function test_facebook_exchanges_the_code_and_creates_an_account(): void
    {
        Http::fake([
            'https://graph.facebook.com/oauth/access_token*' => Http::response(['access_token' => 'fb-access']),
            'https://graph.facebook.com/me*' => Http::response([
                'id' => 'fb-42',
                'name' => 'Uncle FB',
                'email' => 'uncle@example.com',
            ]),
        ]);

        $this->postJson('/api/auth/social/facebook', ['code' => 'fb-code'])
            ->assertCreated()
            ->assertJsonPath('user.name', 'Uncle FB');

        Http::assertSent(fn (Request $request) => str_contains($request->url(), 'oauth/access_token')
            && $request['code'] === 'fb-code'
            && $request['client_secret'] === 'fb-secret'
            && $request['redirect_uri'] === route('auth.facebook.callback'));

        Http::assertSent(fn (Request $request) => str_contains($request->url(), '/me')
            && $request['appsecret_proof'] === hash_hmac('sha256', 'fb-access', 'fb-secret'));
    }

    public function test_facebook_callback_page_returns_to_the_app(): void
    {
        $this->get('/auth/facebook/callback?code=abc&state=xyz')
            ->assertOk()
            ->assertSee('klaikan://auth/facebook?code=abc&amp;state=xyz', false);

        $this->get('/auth/facebook/callback?error=access_denied&state=xyz')
            ->assertOk()
            ->assertSee('error=access_denied', false);
    }

    // =====================================================
    // เชื่อม / ยกเลิกการเชื่อม (หน้าตั้งค่า)
    // =====================================================

    public function test_signed_in_user_can_link_and_unlink_line(): void
    {
        $user = User::factory()->create(['email' => 'daeng@example.com']);

        $this->fakeLine();

        Sanctum::actingAs($user);

        $this->postJson('/api/social-accounts/line', ['id_token' => 'line-token'])
            ->assertOk()
            ->assertJsonPath('has_password', true)
            ->assertJsonPath('accounts.1.provider', 'line')
            ->assertJsonPath('accounts.1.linked', true);

        // จากนี้เข้าสู่ระบบด้วย LINE ได้
        $this->app['auth']->forgetGuards();

        $this->postJson('/api/auth/social/line', ['id_token' => 'line-token'])
            ->assertOk()
            ->assertJsonPath('user.id', $user->id);

        Sanctum::actingAs($user);

        $this->deleteJson('/api/social-accounts/line')
            ->assertOk()
            ->assertJsonPath('accounts.1.linked', false);
    }

    public function test_cannot_link_an_account_that_belongs_to_someone_else(): void
    {
        $owner = User::factory()->create();

        SocialAccount::create([
            'user_id' => $owner->id,
            'provider' => 'line',
            'provider_user_id' => 'U-line-1',
        ]);

        $this->fakeLine();

        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/social-accounts/line', ['id_token' => 'line-token'])
            ->assertStatus(409);
    }

    // =====================================================
    // บัญชีที่ไม่มีรหัสผ่าน
    // =====================================================

    public function test_passwordless_user_must_keep_one_way_to_sign_in(): void
    {
        $this->fakeGoogle();

        $this->postJson('/api/auth/social/google', ['id_token' => 'google-token'])->assertCreated();

        $user = User::firstWhere('email', 'mom@gmail.com');

        Sanctum::actingAs($user);

        $this->deleteJson('/api/social-accounts/google')->assertStatus(422);

        // ตั้งรหัสผ่านได้เลยโดยไม่ต้องใส่รหัสเดิม
        $this->putJson('/api/profile/password', [
            'password' => 'new-password-1',
            'password_confirmation' => 'new-password-1',
        ])->assertOk();

        $this->assertTrue(Hash::check('new-password-1', $user->fresh()->password));

        $this->getJson('/api/profile')->assertJsonPath('user.has_password', true);

        $this->deleteJson('/api/social-accounts/google')->assertOk();

        // มีรหัสผ่านแล้ว → เปลี่ยนต้องใส่รหัสเดิม
        $this->putJson('/api/profile/password', [
            'password' => 'another-pass-2',
            'password_confirmation' => 'another-pass-2',
        ])->assertStatus(422);
    }

    public function test_passwordless_user_requests_deletion_by_typing_confirmation(): void
    {
        $this->fakeLine(['email' => null]);

        $this->postJson('/api/auth/social/line', ['id_token' => 'line-token'])->assertCreated();

        $user = User::firstWhere('name', 'ป้าแดง');

        Sanctum::actingAs($user);

        $this->postJson('/api/account/deletion-request', ['confirm_text' => 'ลบ'])->assertStatus(422);

        $this->postJson('/api/account/deletion-request', ['confirm_text' => 'ลบบัญชี'])
            ->assertOk()
            ->assertJsonPath('request.status', 'pending');

        // ผู้ดูแลอนุมัติ → บัญชีและการเชื่อมต่อถูกลบ
        app(\App\Services\AccountDeletionService::class)->completeRequest(
            \App\Models\AccountDeletionRequest::first(),
            null
        );

        $this->assertNull(User::find($user->id));
        $this->assertSame(0, SocialAccount::count());
    }

    public function test_email_login_does_not_work_without_a_password(): void
    {
        $this->fakeGoogle();

        $this->postJson('/api/auth/social/google', ['id_token' => 'google-token'])->assertCreated();

        $this->app['auth']->forgetGuards();

        $this->postJson('/api/login', [
            'email' => 'mom@gmail.com',
            'password' => 'anything',
        ])->assertStatus(422);
    }
}
