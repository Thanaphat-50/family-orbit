<?php

namespace App\Services;

use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;
use Throwable;

// =======================================================
// ตรวจว่าการเข้าสู่ระบบด้วย Google / LINE / Facebook เป็นของจริง
// ถามผู้ให้บริการโดยตรง (ไม่เชื่อข้อมูลที่แอปส่งมาเอง)
//
// ผลลัพธ์: ['id', 'email', 'email_verified', 'name']
// ตรวจไม่ผ่าน → SocialLoginException (ข้อความภาษาไทยให้ผู้ใช้)
// =======================================================

class SocialIdentityVerifier
{
    public function enabled(string $provider): bool
    {
        return match ($provider) {
            'google' => $this->googleClientIds() !== [],
            'line' => filled(config('services.line.channel_id')),
            'facebook' => filled(config('services.facebook.app_id'))
                && filled(config('services.facebook.app_secret')),
            default => false,
        };
    }

    // ข้อมูลที่แอปต้องใช้เปิดหน้าล็อกอินของแต่ละเจ้า (ไม่มีความลับ)
    public function publicConfig(string $facebookRedirectUri): array
    {
        return [
            'google' => $this->enabled('google') ? [
                'server_client_id' => $this->googleClientIds()[0],
            ] : null,

            'line' => $this->enabled('line') ? [
                'channel_id' => (string) config('services.line.channel_id'),
            ] : null,

            'facebook' => $this->enabled('facebook') ? [
                'auth_url' => 'https://www.facebook.com/' . $this->graphVersionPath() . 'dialog/oauth?' . http_build_query([
                    'client_id' => config('services.facebook.app_id'),
                    'redirect_uri' => $facebookRedirectUri,
                    'response_type' => 'code',
                    'scope' => 'public_profile,email',
                ]),
                'callback_scheme' => 'klaikan',
            ] : null,
        ];
    }

    // credential: google → id_token / line → id_token / facebook → ['code', 'redirect_uri']
    public function verify(string $provider, array $credential): array
    {
        if (!$this->enabled($provider)) {
            throw new SocialLoginException('ยังไม่ได้เปิดใช้การเข้าสู่ระบบด้วยบัญชีนี้');
        }

        try {
            return match ($provider) {
                'google' => $this->verifyGoogle((string) ($credential['id_token'] ?? '')),
                'line' => $this->verifyLine((string) ($credential['id_token'] ?? '')),
                'facebook' => $this->verifyFacebook(
                    (string) ($credential['code'] ?? ''),
                    (string) ($credential['redirect_uri'] ?? '')
                ),
            };
        } catch (SocialLoginException $e) {
            throw $e;
        } catch (Throwable $e) {
            Log::warning('Social login verification failed', [
                'provider' => $provider,
                'error' => $e->getMessage(),
            ]);

            throw new SocialLoginException('เชื่อมต่อผู้ให้บริการไม่สำเร็จ กรุณาลองใหม่');
        }
    }

    // =====================================================
    // Google: ตรวจ ID token กับ Google
    // =====================================================

    private function verifyGoogle(string $idToken): array
    {
        if ($idToken === '') {
            throw new SocialLoginException('ไม่พบข้อมูลการเข้าสู่ระบบจาก Google');
        }

        $response = Http::timeout(10)->get('https://oauth2.googleapis.com/tokeninfo', [
            'id_token' => $idToken,
        ]);

        $this->rejectIfFailed($response, 'Google');

        $data = $response->json();

        $validIssuer = in_array($data['iss'] ?? null, ['accounts.google.com', 'https://accounts.google.com'], true);

        if (
            !$validIssuer
            || !in_array($data['aud'] ?? null, $this->googleClientIds(), true)
            || (int) ($data['exp'] ?? 0) < time()
            || empty($data['sub'])
        ) {
            throw new SocialLoginException('การเข้าสู่ระบบด้วย Google ไม่ถูกต้อง');
        }

        return [
            'id' => (string) $data['sub'],
            'email' => $data['email'] ?? null,
            'email_verified' => ($data['email_verified'] ?? null) === true
                || ($data['email_verified'] ?? null) === 'true',
            'name' => $data['name'] ?? null,
        ];
    }

    // =====================================================
    // LINE: ตรวจ ID token กับ LINE
    // =====================================================

    private function verifyLine(string $idToken): array
    {
        if ($idToken === '') {
            throw new SocialLoginException('ไม่พบข้อมูลการเข้าสู่ระบบจาก LINE');
        }

        $channelId = (string) config('services.line.channel_id');

        $response = Http::asForm()->timeout(10)->post('https://api.line.me/oauth2/v2.1/verify', [
            'id_token' => $idToken,
            'client_id' => $channelId,
        ]);

        $this->rejectIfFailed($response, 'LINE');

        $data = $response->json();

        if (
            ($data['iss'] ?? null) !== 'https://access.line.me'
            || (string) ($data['aud'] ?? '') !== $channelId
            || empty($data['sub'])
        ) {
            throw new SocialLoginException('การเข้าสู่ระบบด้วย LINE ไม่ถูกต้อง');
        }

        return [
            'id' => (string) $data['sub'],
            'email' => $data['email'] ?? null,
            // LINE ไม่ได้ยืนยันว่าอีเมลเป็นของเจ้าของบัญชีจริง → ไม่ใช้ผูกกับบัญชีเดิมอัตโนมัติ
            'email_verified' => false,
            'name' => $data['name'] ?? null,
        ];
    }

    // =====================================================
    // Facebook: แลก code เป็น access token แล้วอ่านข้อมูลผู้ใช้
    // =====================================================

    private function verifyFacebook(string $code, string $redirectUri): array
    {
        if ($code === '' || $redirectUri === '') {
            throw new SocialLoginException('ไม่พบข้อมูลการเข้าสู่ระบบจาก Facebook');
        }

        $graph = 'https://graph.facebook.com/' . $this->graphVersionPath();

        $secret = (string) config('services.facebook.app_secret');

        $tokenResponse = Http::timeout(10)->get($graph . 'oauth/access_token', [
            'client_id' => config('services.facebook.app_id'),
            'client_secret' => $secret,
            'redirect_uri' => $redirectUri,
            'code' => $code,
        ]);

        $this->rejectIfFailed($tokenResponse, 'Facebook');

        $accessToken = (string) $tokenResponse->json('access_token');

        if ($accessToken === '') {
            throw new SocialLoginException('การเข้าสู่ระบบด้วย Facebook ไม่ถูกต้อง');
        }

        $meResponse = Http::timeout(10)->get($graph . 'me', [
            'fields' => 'id,name,email',
            'access_token' => $accessToken,
            'appsecret_proof' => hash_hmac('sha256', $accessToken, $secret),
        ]);

        $this->rejectIfFailed($meResponse, 'Facebook');

        $data = $meResponse->json();

        if (empty($data['id'])) {
            throw new SocialLoginException('การเข้าสู่ระบบด้วย Facebook ไม่ถูกต้อง');
        }

        return [
            'id' => (string) $data['id'],
            'email' => $data['email'] ?? null,
            // ไม่ใช้ผูกกับบัญชีเดิมอัตโนมัติ
            'email_verified' => false,
            'name' => $data['name'] ?? null,
        ];
    }

    // =====================================================
    // Helpers
    // =====================================================

    private function googleClientIds(): array
    {
        return array_values(array_filter(array_map(
            'trim',
            explode(',', (string) config('services.google.client_ids'))
        )));
    }

    // เช่น "v23.0/" (ว่าง = ใช้เวอร์ชันที่ตั้งไว้ในแอป Facebook)
    private function graphVersionPath(): string
    {
        $version = trim((string) config('services.facebook.graph_version'), '/ ');

        return $version === '' ? '' : $version . '/';
    }

    private function rejectIfFailed(Response $response, string $provider): void
    {
        if ($response->successful()) {
            return;
        }

        // 4xx = ข้อมูลเข้าสู่ระบบหมดอายุ / ไม่ถูกต้อง
        if ($response->clientError()) {
            throw new SocialLoginException('การเข้าสู่ระบบด้วย ' . $provider . ' หมดอายุหรือไม่ถูกต้อง กรุณาลองใหม่');
        }

        throw new RuntimeException($provider . ' responded with HTTP ' . $response->status());
    }
}
