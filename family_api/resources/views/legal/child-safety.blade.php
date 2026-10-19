@extends('layouts.public')

@section('title', 'มาตรฐานความปลอดภัยของเด็ก')
@section('robots', 'index')
@section('main_class', 'wide')

@section('content')
<div class="legal">
    <h1>มาตรฐานความปลอดภัยของเด็ก</h1>
    <p class="updated">มีผลตั้งแต่ {{ config('legal.effective_date') }}</p>

    <p>
        แอป {{ $app }} <strong>ไม่ยอมรับการล่วงละเมิดและการแสวงหาประโยชน์ทางเพศจากเด็ก (CSAE)
        และสื่อการล่วงละเมิดทางเพศเด็ก (CSAM) ในทุกรูปแบบ</strong>
        ข้อห้ามนี้ใช้กับโพสต์ ความคิดเห็น รูป ร้านค้า และสินค้าทั้งหมดในแอป
    </p>

    <h2>1. สิ่งที่ห้ามเด็ดขาด</h2>
    <ul>
        <li>รูป วิดีโอ หรือข้อความที่แสดงหรือส่งเสริมการล่วงละเมิดทางเพศเด็ก</li>
        <li>การเข้าหาเด็กเพื่อจุดประสงค์ทางเพศ (grooming) หรือการชักชวนให้เด็กส่งรูปหรือพบกัน</li>
        <li>การค้ามนุษย์ หรือการแสวงหาประโยชน์จากเด็กในรูปแบบใดก็ตาม</li>
        <li>การเปิดเผยข้อมูลส่วนตัวหรือตำแหน่งของเด็กต่อสาธารณะ</li>
    </ul>

    <h2>2. เราป้องกันอย่างไร</h2>
    <ul>
        <li>ตำแหน่งของสมาชิกแสดงเฉพาะในครอบครัวเดียวกัน ไม่แสดงในชุมชนหรือตลาด</li>
        <li>ผู้ใช้ต้องยอมรับกฎชุมชนก่อนโพสต์ในชุมชนครั้งแรก</li>
        <li>รายงานโพสต์ ความคิดเห็น สินค้า และร้านค้าได้ในแอป และบล็อกผู้ใช้ได้</li>
        <li>เนื้อหาที่ถูกรายงานจากผู้ใช้หลายคนจะถูกซ่อนทันทีเพื่อรอผู้ดูแลตรวจสอบ</li>
        <li>ร้านค้าต้องผ่านการตรวจสอบจากผู้ดูแลก่อนแสดงในตลาด</li>
    </ul>

    <h2>3. เมื่อพบเนื้อหาที่ผิดมาตรฐานนี้</h2>
    <ul>
        <li>ลบเนื้อหาทันทีที่ตรวจพบหรือได้รับรายงาน</li>
        <li>ระงับบัญชีผู้กระทำผิดอย่างถาวร</li>
        <li>เก็บหลักฐานที่จำเป็น และแจ้งเจ้าหน้าที่ตำรวจและหน่วยงานที่เกี่ยวข้องตามกฎหมาย</li>
    </ul>

    <h2>4. วิธีรายงาน</h2>
    <ul>
        <li>ในแอป: กด ⋯ ที่โพสต์หรือความคิดเห็น หรือเมนูที่หน้าสินค้า/ร้านค้า แล้วเลือก “รายงาน”</li>
        @if (config('legal.support_email'))
            <li>อีเมลผู้รับผิดชอบด้านความปลอดภัยของเด็ก:
                <a href="mailto:{{ config('legal.support_email') }}">{{ config('legal.support_email') }}</a></li>
        @endif
        <li>หากเด็กตกอยู่ในอันตราย ให้แจ้งตำรวจที่ 191 ทันที</li>
    </ul>

    <h2>English summary</h2>
    <p>
        {{ $app }} has zero tolerance for child sexual abuse and exploitation (CSAE) and child sexual
        abuse material (CSAM). Users can report posts, comments, products and shops in the app.
        Reported content is hidden for review; violating content is removed, the account is banned,
        and we report to law enforcement as required by law.
        @if (config('legal.support_email'))
            Child safety contact: {{ config('legal.support_email') }}.
        @endif
    </p>
</div>
@endsection
