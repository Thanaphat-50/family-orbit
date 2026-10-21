@extends('layouts.public')

@section('title', 'ลบบัญชี')

@section('content')
    <h1>ลบบัญชีและข้อมูลของคุณ</h1>

    <div class="card">
        <h2>ข้อมูลที่จะถูกลบถาวร</h2>
        <ul>
            <li>บัญชีและโปรไฟล์ รวมถึงรูปโปรไฟล์</li>
            <li>การเป็นสมาชิกครอบครัว และตำแหน่งล่าสุด</li>
            <li>โพสต์ ความคิดเห็น และกิจกรรมทั้งหมดของคุณ</li>
            <li>การแจ้งเตือน รายงาน และรายชื่อผู้ใช้ที่บล็อก</li>
        </ul>
    </div>

    <div class="card warning">
        ลบแล้วกู้คืนไม่ได้
        หากคุณเป็น Owner ของครอบครัวที่ยังมีสมาชิกอยู่
        กรุณาโอนสิทธิ์ Owner ในแอปก่อน
    </div>

    <div class="card">
        <p class="muted" style="margin-top: 0">
            ลบในแอปได้ที่ <strong>ตั้งค่า → ลบบัญชี</strong>
            หรือยืนยันด้วยอีเมลและรหัสผ่านด้านล่าง
        </p>

        <form method="POST" action="{{ route('account.delete.submit') }}">
            @csrf

            @if ($errors->any())
                <div class="errors">
                    @foreach ($errors->all() as $error)
                        <div>{{ $error }}</div>
                    @endforeach
                </div>
            @endif

            <label for="email">อีเมล</label>
            <input id="email" type="email" name="email" value="{{ old('email') }}" required autocomplete="email">

            <label for="password">รหัสผ่าน</label>
            <input id="password" type="password" name="password" required autocomplete="current-password">

            <label class="check">
                <input type="checkbox" name="confirm" value="1" required>
                <span>ฉันเข้าใจว่าบัญชีและข้อมูลทั้งหมดจะถูกลบถาวร</span>
            </label>

            <button type="submit">ลบบัญชีถาวร</button>
        </form>
    </div>
@endsection
