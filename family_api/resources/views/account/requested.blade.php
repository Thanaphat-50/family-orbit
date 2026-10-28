@extends('layouts.public')

@section('title', 'ส่งคำขอลบบัญชีแล้ว')

@section('content')
    <div class="card" style="text-align: center; margin-top: 24px">
        <div class="success">✓</div>
        <h1 style="margin-top: 12px">ส่งคำขอลบบัญชีแล้ว</h1>
        <p class="muted">
            ทีมงานจะลบบัญชีและข้อมูลทั้งหมดของคุณให้ภายใน {{ $days }} วัน
            ระหว่างนี้ถ้าเปลี่ยนใจ ยกเลิกคำขอได้ในแอป {{ config('legal.app_name') }}
            ที่ ตั้งค่า → ขอลบบัญชี
        </p>
    </div>
@endsection
