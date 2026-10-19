@extends('layouts.public')

@section('title', 'ลบบัญชีแล้ว')

@section('content')
    <div class="card" style="text-align: center; margin-top: 24px">
        <div class="success">✓</div>
        <h1 style="margin-top: 12px">ลบบัญชีเรียบร้อยแล้ว</h1>
        <p class="muted">
            บัญชีและข้อมูลทั้งหมดของคุณถูกลบออกจากระบบแล้ว
            ขอบคุณที่เคยใช้ {{ config('legal.app_name') }}
        </p>
    </div>
@endsection
