<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // =====================================================
        // Rate Limit: Login
        //
        // - Email เดียวกันจาก IP เดียวกัน ลองได้ 5 ครั้ง/นาที
        //   (กันการเดารหัสผ่านของบัญชีใดบัญชีหนึ่ง)
        // - IP เดียวกัน ลองได้รวม 20 ครั้ง/นาที
        //   (กันการไล่เดาหลายบัญชีจากเครื่องเดียว)
        // =====================================================

        RateLimiter::for('login', function (Request $request) {
            $email = Str::lower(
                trim((string) $request->input('email'))
            );

            return [
                Limit::perMinute(5)
                    ->by('login-email:' . $email . '|' . $request->ip())
                    ->response($this->tooManyAttempts(...)),

                Limit::perMinute(20)
                    ->by('login-ip:' . $request->ip())
                    ->response($this->tooManyAttempts(...)),
            ];
        });

        // =====================================================
        // Rate Limit: Register
        //
        // - IP เดียวกัน สมัครได้ 5 ครั้ง/นาที
        //   (กันการสร้างบัญชีปลอมจำนวนมาก)
        // =====================================================

        RateLimiter::for('register', function (Request $request) {
            return Limit::perMinute(5)
                ->by('register-ip:' . $request->ip())
                ->response($this->tooManyAttempts(...));
        });

        // =====================================================
        // Rate Limit: โพสต์ / ความคิดเห็น / รายงาน
        //
        // - ผู้ใช้คนเดียว รวมกันได้ 20 ครั้ง/นาที
        //   (กันสแปมในฟีดชุมชน)
        // =====================================================

        RateLimiter::for('ugc', function (Request $request) {
            return Limit::perMinute(20)
                ->by('ugc:' . ($request->user()?->id ?? $request->ip()))
                ->response($this->tooManyAttempts(...));
        });
    }

    // =====================================================
    // Response เมื่อลองเกินกำหนด (HTTP 429)
    // รูปแบบเดียวกับ API อื่น ๆ: status + message
    // =====================================================

    private function tooManyAttempts(
        Request $request,
        array $headers
    ): JsonResponse {
        $seconds = (int) ($headers['Retry-After'] ?? 60);

        return response()->json([
            'status' => false,
            'message' =>
                'ลองหลายครั้งเกินไป กรุณารอ '
                . $seconds
                . ' วินาทีแล้วลองใหม่',
            'retry_after' => $seconds,
        ], 429, $headers);
    }
}
