<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;

// =======================================================
// ตั้งผู้ใช้เป็นผู้ดูแลระบบ (เข้าหน้า /admin ได้)
//
// php artisan app:make-admin you@example.com
// php artisan app:make-admin you@example.com --revoke
// =======================================================

class MakeAdmin extends Command
{
    protected $signature = 'app:make-admin
        {email : อีเมลของบัญชีที่ต้องการตั้งเป็น Admin}
        {--revoke : ถอนสิทธิ์ Admin แทน}';

    protected $description = 'ตั้งหรือถอนสิทธิ์ผู้ดูแลระบบของบัญชี';

    public function handle(): int
    {
        $user = User::where('email', $this->argument('email'))->first();

        if (!$user) {
            $this->error('ไม่พบบัญชีที่ใช้อีเมลนี้');

            return self::FAILURE;
        }

        $revoke = (bool) $this->option('revoke');

        $user->is_admin = !$revoke;
        $user->save();

        $this->info(
            $revoke
                ? "ถอนสิทธิ์ Admin ของ {$user->name} แล้ว"
                : "ตั้ง {$user->name} เป็น Admin แล้ว"
        );

        return self::SUCCESS;
    }
}
