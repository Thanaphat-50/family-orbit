{{-- ช่องทางติดต่อ (ใช้ร่วมกันทุกหน้านโยบาย) --}}
<ul>
    @if (config('legal.support_email'))
        <li>อีเมล: <a href="mailto:{{ config('legal.support_email') }}">{{ config('legal.support_email') }}</a></li>
    @endif
    <li>ในแอป: กดปุ่ม “รายงาน” ที่โพสต์ ความคิดเห็น สินค้า หรือร้านค้า</li>
    <li>ขอลบบัญชี: <a href="{{ route('account.delete') }}">{{ route('account.delete') }}</a></li>
</ul>
