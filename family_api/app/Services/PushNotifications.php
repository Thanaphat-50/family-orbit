<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\DeviceToken;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;
use Throwable;

// =======================================================
// ส่งแจ้งเตือนเด้งผ่าน Firebase Cloud Messaging (HTTP v1)
//
// ใช้ Service account ของ Firebase project (ไม่ต้องติดตั้งแพ็กเกจเพิ่ม)
// - FIREBASE_CREDENTIALS_BASE64: ไฟล์ JSON ทั้งไฟล์ แปลงเป็น base64 (ตั้งใน Laravel Cloud)
// - FIREBASE_CREDENTIALS_PATH:   path ของไฟล์ JSON (ใช้ในเครื่อง)
// ไม่ได้ตั้งค่า → ไม่ส่ง (ยังเห็นในหน้าแจ้งเตือนในแอปตามปกติ)
// =======================================================

class PushNotifications
{
    private const TOKEN_URL = 'https://oauth2.googleapis.com/token';

    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    // ช่องแจ้งเตือนบน Android (สร้างไว้ใน MainActivity.kt)
    public const ANDROID_CHANNEL = 'klaikan_default';

    // ไอคอนบนแถบสถานะ (res/drawable/ic_stat_notify.xml)
    private const ANDROID_ICON = 'ic_stat_notify';

    private ?array $credentials = null;

    private bool $credentialsLoaded = false;

    public function enabled(): bool
    {
        return $this->credentials() !== null;
    }

    // ส่งการแจ้งเตือนนี้ไปทุกเครื่องที่ผู้รับยังล็อกอินอยู่
    public function sendNotification(AppNotification $notification): void
    {
        if (!$this->enabled()) {
            return;
        }

        $tokens = DeviceToken::where('user_id', $notification->user_id)
            ->loggedIn()
            ->pluck('token');

        if ($tokens->isEmpty()) {
            return;
        }

        $data = $this->dataPayload($notification);

        foreach ($tokens as $token) {
            $this->sendToToken(
                $token,
                (string) $notification->title,
                (string) $notification->message,
                $data
            );
        }
    }

    private function sendToToken(string $token, string $title, string $body, array $data): void
    {
        try {
            $response = Http::withToken($this->accessToken())
                ->timeout(10)
                ->post($this->sendUrl(), [
                    'message' => [
                        // รหัสเครื่องแบบใหม่ของ Firebase (FID) — field token เดิมเลิกใช้แล้ว
                        'fid' => $token,
                        'notification' => [
                            'title' => $title,
                            'body' => $body,
                        ],
                        'data' => $data,
                        'android' => [
                            'priority' => 'high',
                            'notification' => [
                                'channel_id' => self::ANDROID_CHANNEL,
                                'icon' => self::ANDROID_ICON,
                                'color' => '#5B5FEF',
                            ],
                        ],
                    ],
                ]);
        } catch (Throwable $e) {
            Log::warning('FCM send failed', ['error' => $e->getMessage()]);

            return;
        }

        if ($response->successful()) {
            return;
        }

        // ถอนแอป / ออกจากระบบในเครื่องนั้นแล้ว → ไม่ต้องส่งไปอีก
        if ($this->isDeadToken($response)) {
            DeviceToken::where('token', $token)->delete();

            return;
        }

        // access token ใช้ไม่ได้แล้ว → รอบหน้าขอใหม่
        if ($response->status() === 401) {
            Cache::forget($this->accessTokenCacheKey());
        }

        Log::warning('FCM send failed', [
            'status' => $response->status(),
            'error' => $response->json('error.status'),
        ]);
    }

    private function isDeadToken(Response $response): bool
    {
        $errorCodes = collect($response->json('error.details', []))
            ->pluck('errorCode');

        if ($response->status() === 404 || $errorCodes->contains('UNREGISTERED')) {
            return true;
        }

        // token ผิดรูปแบบ (400 ด้วยเหตุอื่น เช่น ข้อมูลที่ส่งผิด จะไม่ลบ token)
        return $response->status() === 400
            && str_contains((string) $response->json('error.message'), 'registration token');
    }

    // FCM รับ data เป็นข้อความเท่านั้น
    // แอปใช้ type + id ต่าง ๆ เปิดหน้าที่เกี่ยวข้องเมื่อกดแจ้งเตือน
    private function dataPayload(AppNotification $notification): array
    {
        $data = [
            'type' => (string) $notification->type,
            'notification_id' => (string) $notification->id,
        ];

        foreach ((array) $notification->data as $key => $value) {
            if (is_scalar($value)) {
                $data[(string) $key] = (string) $value;
            }
        }

        return $data;
    }

    private function sendUrl(): string
    {
        return 'https://fcm.googleapis.com/v1/projects/'
            . $this->credentials()['project_id']
            . '/messages:send';
    }

    // =====================================================
    // Access token (อายุ 1 ชม. เก็บไว้ใช้ซ้ำ 50 นาที)
    // =====================================================

    private function accessTokenCacheKey(): string
    {
        return 'fcm.access_token.' . $this->credentials()['project_id'];
    }

    private function accessToken(): string
    {
        return Cache::remember(
            $this->accessTokenCacheKey(),
            now()->addMinutes(50),
            function () {
                $credentials = $this->credentials();

                $now = time();

                $assertion = $this->signedJwt([
                    'iss' => $credentials['client_email'],
                    'scope' => self::SCOPE,
                    'aud' => self::TOKEN_URL,
                    'iat' => $now,
                    'exp' => $now + 3600,
                ], $credentials['private_key']);

                $response = Http::asForm()
                    ->timeout(10)
                    ->post(self::TOKEN_URL, [
                        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                        'assertion' => $assertion,
                    ]);

                $token = $response->json('access_token');

                if (!$response->successful() || !is_string($token) || $token === '') {
                    throw new RuntimeException(
                        'FCM access token request failed (HTTP ' . $response->status() . ')'
                    );
                }

                return $token;
            }
        );
    }

    private function signedJwt(array $claims, string $privateKey): string
    {
        $input = $this->base64Url(json_encode(['alg' => 'RS256', 'typ' => 'JWT']))
            . '.'
            . $this->base64Url(json_encode($claims));

        if (!openssl_sign($input, $signature, $privateKey, OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('FCM: cannot sign the access token request');
        }

        return $input . '.' . $this->base64Url($signature);
    }

    private function base64Url(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    // =====================================================
    // Service account
    // =====================================================

    private function credentials(): ?array
    {
        if ($this->credentialsLoaded) {
            return $this->credentials;
        }

        $this->credentialsLoaded = true;

        $encoded = config('services.fcm.credentials');

        $path = config('services.fcm.credentials_path');

        $json = null;

        if (is_string($encoded) && trim($encoded) !== '') {
            $json = base64_decode(trim($encoded), true);
        } elseif (is_string($path) && $path !== '' && is_file($path)) {
            $json = file_get_contents($path);
        }

        if (!is_string($json) || $json === '') {
            return null;
        }

        $data = json_decode($json, true);

        if (
            !is_array($data)
            || empty($data['project_id'])
            || empty($data['client_email'])
            || empty($data['private_key'])
        ) {
            Log::warning('FCM credentials are set but invalid');

            return null;
        }

        return $this->credentials = $data;
    }
}
