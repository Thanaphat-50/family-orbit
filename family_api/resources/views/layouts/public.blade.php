<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="@yield('robots', 'noindex')">
    <title>@yield('title') · {{ config('legal.app_name') }}</title>
    <style>
        :root {
            --navy: #111827;
            --primary: #5B5FEF;
            --muted: #667085;
            --border: #E7E9F2;
            --danger: #E5484D;
            --success: #2E9D6A;
            --background: #F6F7FB;
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            min-height: 100vh;
            background: var(--background);
            color: var(--navy);
            font-family: -apple-system, "Segoe UI", "Noto Sans Thai", "Leelawadee UI", Tahoma, sans-serif;
            line-height: 1.6;
        }

        main {
            max-width: 520px;
            margin: 0 auto;
            padding: 32px 16px 48px;
        }

        .brand {
            color: var(--primary);
            font-size: 12px;
            font-weight: 800;
            letter-spacing: 1.5px;
        }

        h1 {
            margin: 6px 0 18px;
            font-size: 26px;
            line-height: 1.3;
        }

        .card {
            background: #fff;
            border: 1px solid var(--border);
            border-radius: 20px;
            padding: 20px;
            margin-bottom: 16px;
        }

        .card h2 {
            margin: 0 0 8px;
            font-size: 16px;
        }

        ul {
            margin: 0;
            padding-left: 20px;
            color: var(--muted);
        }

        .muted { color: var(--muted); }

        .warning {
            background: #FFF1F1;
            border-color: #F6C9CB;
            color: #9B1C20;
        }

        label {
            display: block;
            margin: 14px 0 6px;
            font-weight: 700;
            font-size: 14px;
        }

        input[type="email"],
        input[type="password"] {
            width: 100%;
            padding: 13px 14px;
            border: 1px solid var(--border);
            border-radius: 14px;
            font-size: 15px;
        }

        input:focus {
            outline: 2px solid var(--primary);
            border-color: transparent;
        }

        .check {
            display: flex;
            gap: 10px;
            align-items: flex-start;
            margin-top: 16px;
            font-weight: 600;
            font-size: 14px;
        }

        .check input { margin-top: 5px; }

        button {
            width: 100%;
            margin-top: 20px;
            padding: 14px;
            border: 0;
            border-radius: 14px;
            background: var(--danger);
            color: #fff;
            font-size: 16px;
            font-weight: 800;
            cursor: pointer;
        }

        .errors {
            background: #FFF1F1;
            border: 1px solid #F6C9CB;
            color: #9B1C20;
            border-radius: 14px;
            padding: 12px 14px;
            margin-bottom: 4px;
            font-size: 14px;
        }

        .success {
            color: var(--success);
            font-size: 48px;
            line-height: 1;
        }

        /* หน้านโยบาย: กว้างขึ้น อ่านง่าย */
        main.wide { max-width: 720px; }

        .legal h2 {
            margin: 28px 0 8px;
            font-size: 18px;
        }

        .legal p,
        .legal li { color: #344054; }

        .legal li { margin-bottom: 4px; }

        .legal ul { color: #344054; }

        .legal table {
            width: 100%;
            border-collapse: collapse;
            font-size: 14px;
            margin: 8px 0;
        }

        .legal th,
        .legal td {
            border: 1px solid var(--border);
            padding: 8px 10px;
            text-align: left;
            vertical-align: top;
        }

        .legal th { background: #fff; }

        .updated {
            color: var(--muted);
            font-size: 14px;
            margin-top: -10px;
        }

        a { color: var(--primary); }

        footer {
            margin-top: 36px;
            padding-top: 18px;
            border-top: 1px solid var(--border);
            font-size: 14px;
            color: var(--muted);
        }

        footer a {
            margin-right: 14px;
            white-space: nowrap;
        }
    </style>
</head>
<body>
    <main class="@yield('main_class')">
        <div class="brand">{{ config('legal.app_name') }}</div>
        @yield('content')

        <footer>
            <a href="{{ route('legal.privacy') }}">นโยบายความเป็นส่วนตัว</a>
            <a href="{{ route('legal.terms') }}">ข้อกำหนดการใช้งาน</a>
            <a href="{{ route('legal.child-safety') }}">ความปลอดภัยของเด็ก</a>
            <a href="{{ route('account.delete') }}">ลบบัญชี</a>
            @if (config('legal.support_email'))
                <div style="margin-top: 8px">
                    ติดต่อ: <a href="mailto:{{ config('legal.support_email') }}">{{ config('legal.support_email') }}</a>
                </div>
            @endif
        </footer>
    </main>
</body>
</html>
