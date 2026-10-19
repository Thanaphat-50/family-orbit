<?php

namespace Tests\Feature;

use Tests\TestCase;

class LegalPagesTest extends TestCase
{
    // =====================================================
    // หน้านโยบายที่ใส่ใน Google Play ต้องเปิดได้โดยไม่ต้อง Login
    // =====================================================

    public function test_legal_pages_are_public(): void
    {
        $this->get('/privacy')
            ->assertOk()
            ->assertSee('นโยบายความเป็นส่วนตัว')
            ->assertSee('เก็บเฉพาะตำแหน่งล่าสุดเท่านั้น')
            ->assertSee(route('account.delete'));

        $this->get('/terms')
            ->assertOk()
            ->assertSee('ข้อกำหนดการใช้งาน')
            ->assertSee('ไม่ได้เป็นคู่สัญญาซื้อขาย');

        $this->get('/child-safety')
            ->assertOk()
            ->assertSee('CSAE');
    }

    public function test_support_email_is_shown_when_configured(): void
    {
        config(['legal.support_email' => null]);

        $this->get('/privacy')->assertDontSee('mailto:', false);

        config(['legal.support_email' => 'help@example.com']);

        $this->get('/privacy')->assertSee('mailto:help@example.com', false);
        $this->get('/child-safety')->assertSee('help@example.com');
    }

    public function test_account_delete_page_uses_shared_layout(): void
    {
        $this->get('/account/delete')
            ->assertOk()
            ->assertSee(route('legal.privacy'));
    }
}
