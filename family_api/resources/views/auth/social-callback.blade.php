@extends('layouts.public')

@section('title', 'กำลังกลับเข้าแอป')

@section('content')
    {{-- Facebook ส่งกลับมาหน้านี้ → เปิดแอปต่อทันที (กดปุ่มเองได้ถ้าไม่เปิด) --}}
    <div class="card" style="text-align: center; margin-top: 24px">
        <h1 style="margin-top: 4px">กำลังกลับเข้าแอป {{ config('legal.app_name') }}</h1>
        <p class="muted">ถ้าแอปไม่เปิดเอง กดปุ่มด้านล่าง</p>
        <p style="margin-top: 18px">
            <a class="button" id="open-app" href="{{ $appUrl }}">เปิดแอป</a>
        </p>
    </div>

    <script>
        window.location.replace(@json($appUrl));
    </script>
@endsection
