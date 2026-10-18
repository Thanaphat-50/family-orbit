<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthSecurityTest extends TestCase
{
    use RefreshDatabase;

    // =====================================================
    // Login: ลองผิดเกิน 5 ครั้ง/นาที → 429
    // =====================================================

    public function test_login_is_rate_limited_after_five_attempts(): void
    {
        User::factory()->create([
            'email' => 'mom@example.com',
        ]);

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/login', [
                'email' => 'mom@example.com',
                'password' => 'wrong-password',
            ])->assertStatus(422);
        }

        $this->postJson('/api/login', [
            'email' => 'mom@example.com',
            'password' => 'wrong-password',
        ])
            ->assertStatus(429)
            ->assertHeader('Retry-After')
            ->assertJson(['status' => false]);
    }

    // =====================================================
    // Login: เปลี่ยนตัวพิมพ์เล็ก/ใหญ่ของ Email ก็ยังนับรวมกัน
    // =====================================================

    public function test_login_limit_ignores_email_letter_case(): void
    {
        $emails = [
            'mom@example.com',
            'MOM@example.com',
            'Mom@Example.com',
            'mom@EXAMPLE.com',
            'MoM@example.com',
        ];

        foreach ($emails as $email) {
            $this->postJson('/api/login', [
                'email' => $email,
                'password' => 'wrong-password',
            ])->assertStatus(422);
        }

        $this->postJson('/api/login', [
            'email' => 'MOM@EXAMPLE.COM',
            'password' => 'wrong-password',
        ])->assertStatus(429);
    }

    // =====================================================
    // Register: เกิน 5 ครั้ง/นาที จาก IP เดียวกัน → 429
    // =====================================================

    public function test_register_is_rate_limited_after_five_attempts(): void
    {
        for ($i = 1; $i <= 5; $i++) {
            $this->postJson('/api/register', [
                'name' => 'Member ' . $i,
                'email' => 'member' . $i . '@example.com',
                'password' => 'password123',
                'password_confirmation' => 'password123',
            ])->assertStatus(201);
        }

        $this->postJson('/api/register', [
            'name' => 'Member 6',
            'email' => 'member6@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ])
            ->assertStatus(429)
            ->assertJson(['status' => false]);
    }

    // =====================================================
    // Token: ใช้ได้ภายใน 30 วัน และหมดอายุหลัง 30 วัน
    // =====================================================

    public function test_token_expires_after_thirty_days(): void
    {
        $user = User::factory()->create();

        $token = $user->createToken('family-app')->plainTextToken;

        $this->travel(29)->days();

        $this->withToken($token)
            ->getJson('/api/user')
            ->assertOk();

        // ล้าง User ที่ Guard จำไว้จาก Request ก่อนหน้า
        $this->app['auth']->forgetGuards();

        $this->travel(2)->days();

        $this->withToken($token)
            ->getJson('/api/user')
            ->assertUnauthorized();
    }
}
