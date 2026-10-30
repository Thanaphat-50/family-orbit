<?php

namespace Tests\Feature;

use App\Filament\Resources\Users\Pages\ViewUser;
use App\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use Tests\Concerns\CreatesFamilies;
use Tests\TestCase;

class ProfileIntroTest extends TestCase
{
    use CreatesFamilies, RefreshDatabase;

    public function test_user_saves_intro_and_community_sees_it(): void
    {
        $author = User::factory()->create(['name' => 'Aunt Daeng']);
        $family = $this->createFamily($author);

        Post::create([
            'family_id' => $family->id,
            'user_id' => $author->id,
            'visibility' => 'community',
            'content' => 'Hello',
        ]);

        Sanctum::actingAs($author);

        $this->putJson('/api/profile', [
            'bio' => "  ชอบทำอาหาร\r\n\n\n\nและปลูกต้นไม้  ",
            'occupation' => 'ครู',
            'education' => '',
            'province' => 'เชียงใหม่',
            'interests' => 'ทำอาหาร, ต้นไม้',
        ])
            ->assertOk()
            ->assertJsonPath('message', 'บันทึกโปรไฟล์แล้ว')
            ->assertJsonPath('user.name', 'Aunt Daeng')
            ->assertJsonPath('user.intro.bio', "ชอบทำอาหาร\n\nและปลูกต้นไม้")
            ->assertJsonPath('user.intro.education', null);

        $this->getJson('/api/profile')
            ->assertJsonPath('user.intro.occupation', 'ครู')
            ->assertJsonPath('user.intro.province', 'เชียงใหม่');

        // คนอื่นในชุมชนเห็นข้อมูลแนะนำตัว
        $viewer = User::factory()->create();
        Sanctum::actingAs($viewer);

        $this->getJson("/api/users/{$author->id}/profile")
            ->assertOk()
            ->assertJsonPath('profile.intro.occupation', 'ครู')
            ->assertJsonPath('profile.intro.interests', 'ทำอาหาร, ต้นไม้');

        // ไม่ปนไปกับข้อมูลผู้ใช้ที่ส่งในที่อื่น
        $this->assertArrayNotHasKey('bio', $author->fresh()->toArray());
    }

    public function test_partial_update_keeps_other_fields_and_old_app_still_renames(): void
    {
        $user = User::factory()->create(['name' => 'Old']);

        Sanctum::actingAs($user);

        $this->putJson('/api/profile', ['bio' => 'สวัสดี', 'occupation' => 'หมอ'])->assertOk();

        // แอปเวอร์ชันเก่าส่งแค่ชื่อ
        $this->putJson('/api/profile', ['name' => ' New '])
            ->assertOk()
            ->assertJsonPath('message', 'แก้ไขชื่อเรียบร้อยแล้ว')
            ->assertJsonPath('user.intro.bio', 'สวัสดี');

        $this->putJson('/api/profile', ['occupation' => null])->assertOk();

        $user->refresh();

        $this->assertSame('New', $user->name);
        $this->assertSame('สวัสดี', $user->bio);
        $this->assertNull($user->occupation);
    }

    public function test_intro_validation(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->putJson('/api/profile', ['bio' => str_repeat('ก', 301)])
            ->assertStatus(422)
            ->assertJsonValidationErrors('bio');

        $this->putJson('/api/profile', ['province' => 'ดาวอังคาร'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('province');

        $this->putJson('/api/profile', ['name' => ''])
            ->assertStatus(422)
            ->assertJsonValidationErrors('name');
    }

    public function test_admin_sees_intro_on_user_page(): void
    {
        $admin = User::factory()->create();
        $admin->is_admin = true;
        $admin->save();

        $user = User::factory()->create();
        $user->bio = 'Selling cheap phones, add my LINE';
        $user->save();

        $this->actingAs($admin);

        Livewire::test(ViewUser::class, ['record' => $user->getRouteKey()])
            ->assertSee('แนะนำตัว')
            ->assertSee('Selling cheap phones, add my LINE');
    }
}
