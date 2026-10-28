@extends('layouts.public')

@section('title', 'ขอลบบัญชี')

@section('content')
    <h1>ขอลบบัญชีและข้อมูลของคุณ</h1>

    <div class="card">
        <h2>วิธีการ</h2>
        <p class="muted" style="margin-top: 0">
            ส่งคำขอได้ที่หน้านี้ หรือในแอปที่ <strong>ตั้งค่า → ขอลบบัญชี</strong>
            ทีมงานจะตรวจสอบและลบบัญชีพร้อมข้อมูลทั้งหมดให้ภายใน {{ \App\Models\AccountDeletionRequest::PROCESS_WITHIN_DAYS }} วัน
            ระหว่างรอ คุณยังใช้แอปได้ตามปกติ และยกเลิกคำขอได้ในแอป
        </p>
    </div>

    <div class="card">
        <h2>ข้อมูลที่จะถูกลบถาวร</h2>
        <ul>
            <li>บัญชีและโปรไฟล์ รวมถึงรูปโปรไฟล์ และบัญชี Google / LINE / Facebook ที่เชื่อมไว้</li>
            <li>การเป็นสมาชิกครอบครัว และตำแหน่งล่าสุด</li>
            <li>โพสต์ ความคิดเห็น แชท และกิจกรรมทั้งหมดของคุณ</li>
            <li>ร้านค้า สินค้า และรูปทั้งหมด</li>
            <li>การแจ้งเตือน รายงาน และรายชื่อผู้ใช้ที่บล็อก</li>
        </ul>
        <p class="muted">
            เราเก็บเฉพาะชื่อ อีเมล และวันที่ของคำขอไว้เป็นหลักฐานการลบ
        </p>
    </div>

    <div class="card warning">
        ลบแล้วกู้คืนไม่ได้
        หากคุณเป็น Owner ของครอบครัวที่ยังมีสมาชิกอยู่
        กรุณาโอนสิทธิ์ Owner ในแอปก่อน
    </div>

    <div class="card">
        <p class="muted" style="margin-top: 0">
            ยืนยันตัวตนด้วยอีเมลและรหัสผ่าน
            (ถ้าสมัครด้วย Google, LINE หรือ Facebook และยังไม่ได้ตั้งรหัสผ่าน
            ให้ส่งคำขอในแอปที่ ตั้งค่า → ขอลบบัญชี)
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

            <label for="reason">เหตุผล (ไม่บังคับ)</label>
            <input id="reason" type="text" name="reason" value="{{ old('reason') }}" maxlength="1000">

            <label class="check">
                <input type="checkbox" name="confirm" value="1" required>
                <span>ฉันเข้าใจว่าบัญชีและข้อมูลทั้งหมดจะถูกลบถาวร</span>
            </label>

            <button type="submit">ส่งคำขอลบบัญชี</button>
        </form>
    </div>
@endsection
