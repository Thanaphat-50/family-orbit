<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

// =======================================================
// หน้า Admin ใช้ภาษาไทย (Filament มีคำแปลไทยมาให้)
// ใช้เฉพาะ Panel /admin ไม่กระทบ API ของแอป
// =======================================================

class SetAdminLocale
{
    public function handle(Request $request, Closure $next): Response
    {
        app()->setLocale('th');

        return $next($request);
    }
}
