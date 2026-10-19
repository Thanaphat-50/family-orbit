<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>@yield('title') · FAMILY ORBIT</title>
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
    </style>
</head>
<body>
    <main>
        <div class="brand">FAMILY ORBIT</div>
        @yield('content')
    </main>
</body>
</html>
