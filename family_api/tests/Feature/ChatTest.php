<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Models\DeviceToken;
use App\Models\FamilyMember;
use App\Models\User;
use App\Services\AccountDeletionService;
use App\Support\MediaStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesFamilies;
use Tests\Concerns\FakesImages;
use Tests\TestCase;

class ChatTest extends TestCase
{
    use CreatesFamilies, FakesImages, RefreshDatabase;

    private const FCM_URL = 'https://fcm.googleapis.com/v1/projects/test-project/messages:send';

    private function family(): array
    {
        $mom = User::factory()->create(['name' => 'Mom']);
        $son = User::factory()->create(['name' => 'Son']);

        $family = $this->createFamily($mom, [$son]);

        return [$mom, $son, $family];
    }

    private function openChat(User $me, User $other): int
    {
        Sanctum::actingAs($me);

        return $this->postJson('/api/chats', ['user_id' => $other->id])
            ->assertOk()
            ->json('conversation.id');
    }

    // =====================================================
    // คุยกันในครอบครัว
    // =====================================================

    public function test_family_members_can_chat_and_read_messages(): void
    {
        [$mom, $son] = $this->family();

        $roomId = $this->openChat($mom, $son);

        // เปิดซ้ำได้ห้องเดิม
        $this->assertSame($roomId, $this->openChat($mom, $son));

        $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'กินข้าวยัง'])
            ->assertCreated()
            ->assertJsonPath('message.is_mine', true)
            ->assertJsonPath('message.body', 'กินข้าวยัง');

        // ลูกเห็นข้อความที่ยังไม่อ่าน
        Sanctum::actingAs($son);

        $this->getJson('/api/chats/unread-count')
            ->assertOk()
            ->assertJsonPath('unread_count', 1);

        $this->getJson('/api/chats')
            ->assertOk()
            ->assertJsonPath('conversations.0.id', $roomId)
            ->assertJsonPath('conversations.0.user.name', 'Mom')
            ->assertJsonPath('conversations.0.unread_count', 1)
            ->assertJsonPath('conversations.0.last_message.body', 'กินข้าวยัง')
            ->assertJsonPath('conversations.0.can_send', true)
            ->assertJsonPath('contacts.0.id', $mom->id)
            ->assertJsonPath('contacts.0.conversation_id', $roomId);

        // เปิดห้อง = อ่านแล้ว
        $this->getJson("/api/chats/{$roomId}/messages")
            ->assertOk()
            ->assertJsonCount(1, 'messages')
            ->assertJsonPath('messages.0.is_mine', false);

        $this->getJson('/api/chats/unread-count')->assertJsonPath('unread_count', 0);

        $reply = $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'กินแล้วครับ'])
            ->assertCreated()
            ->json('message.id');

        // ดึงเฉพาะข้อความใหม่
        Sanctum::actingAs($mom);

        $this->getJson("/api/chats/{$roomId}/messages?after_id=" . ($reply - 1))
            ->assertOk()
            ->assertJsonCount(1, 'messages')
            ->assertJsonPath('messages.0.body', 'กินแล้วครับ')
            // ลูกอ่านข้อความของแม่แล้ว → แม่เห็น "อ่านแล้ว"
            ->assertJsonPath('conversation.other_read_id', $reply);
    }

    public function test_chat_list_without_any_chats_shows_family_contacts(): void
    {
        [$mom, $son] = $this->family();

        Sanctum::actingAs($mom);

        $this->getJson('/api/chats')
            ->assertOk()
            ->assertJsonCount(0, 'conversations')
            ->assertJsonPath('contacts.0.id', $son->id)
            ->assertJsonPath('contacts.0.name', 'Son')
            ->assertJsonPath('contacts.0.conversation_id', null);

        // ไม่มีครอบครัว → ไม่มีรายชื่อ
        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/chats')
            ->assertOk()
            ->assertJsonCount(0, 'contacts');
    }

    public function test_older_messages_are_paged(): void
    {
        [$mom, $son] = $this->family();

        $roomId = $this->openChat($mom, $son);

        for ($i = 1; $i <= 35; $i++) {
            ChatMessage::create([
                'conversation_id' => $roomId,
                'sender_id' => $mom->id,
                'body' => 'Message ' . $i,
            ]);
        }

        $latest = $this->getJson("/api/chats/{$roomId}/messages")
            ->assertOk()
            ->assertJsonCount(30, 'messages')
            ->assertJsonPath('has_more', true)
            ->assertJsonPath('messages.29.body', 'Message 35');

        $oldestShown = $latest->json('messages.0.id');

        $this->getJson("/api/chats/{$roomId}/messages?before_id={$oldestShown}")
            ->assertOk()
            ->assertJsonCount(5, 'messages')
            ->assertJsonPath('has_more', false)
            ->assertJsonPath('messages.0.body', 'Message 1');
    }

    // =====================================================
    // เฉพาะคนในครอบครัว
    // =====================================================

    public function test_cannot_chat_with_people_outside_the_family(): void
    {
        [$mom] = $this->family();

        $stranger = User::factory()->create();
        $this->createFamily($stranger);

        Sanctum::actingAs($mom);

        $this->postJson('/api/chats', ['user_id' => $stranger->id])->assertForbidden();
        $this->postJson('/api/chats', ['user_id' => $mom->id])->assertStatus(422);

        $this->assertSame(0, Conversation::count());
    }

    public function test_outsiders_cannot_read_or_post_in_a_room(): void
    {
        [$mom, $son] = $this->family();

        $roomId = $this->openChat($mom, $son);

        $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'secret'])->assertCreated();

        Sanctum::actingAs(User::factory()->create());

        $this->getJson("/api/chats/{$roomId}/messages")->assertNotFound();
        $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'hi'])->assertNotFound();
    }

    public function test_after_leaving_the_family_history_stays_but_sending_stops(): void
    {
        [$mom, $son] = $this->family();

        $roomId = $this->openChat($mom, $son);

        $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'before'])->assertCreated();

        FamilyMember::where('user_id', $son->id)->delete();

        $this->getJson("/api/chats/{$roomId}/messages")
            ->assertOk()
            ->assertJsonPath('conversation.can_send', false)
            ->assertJsonCount(1, 'messages');

        $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'after'])->assertForbidden();
    }

    public function test_blocked_people_cannot_message(): void
    {
        [$mom, $son] = $this->family();

        $roomId = $this->openChat($mom, $son);

        Sanctum::actingAs($son);
        $this->postJson('/api/users/' . $mom->id . '/block')->assertOk();

        Sanctum::actingAs($mom);
        $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'hello?'])->assertForbidden();
    }

    public function test_message_needs_text_or_image(): void
    {
        [$mom, $son] = $this->family();

        $roomId = $this->openChat($mom, $son);

        $this->postJson("/api/chats/{$roomId}/messages", ['body' => ''])->assertStatus(422);
        $this->postJson("/api/chats/{$roomId}/messages", ['body' => '   '])->assertStatus(422);

        $this->assertSame(0, ChatMessage::count());
    }

    // =====================================================
    // รูป + ยกเลิกการส่ง
    // =====================================================

    public function test_image_message_is_stored_and_removed_when_unsent(): void
    {
        Storage::fake(MediaStorage::disk());

        [$mom, $son] = $this->family();

        $roomId = $this->openChat($mom, $son);

        $sent = $this->post("/api/chats/{$roomId}/messages", [
            'image' => $this->fakePng(),
        ], ['Accept' => 'application/json'])->assertCreated();

        $this->assertNotNull($sent->json('message.image_url'));

        $path = ChatMessage::first()->image_path;

        Storage::disk(MediaStorage::disk())->assertExists($path);

        // อีกฝ่ายยกเลิกข้อความของเราไม่ได้
        Sanctum::actingAs($son);
        $this->deleteJson("/api/chats/{$roomId}/messages/" . $sent->json('message.id'))->assertForbidden();

        Sanctum::actingAs($mom);
        $this->deleteJson("/api/chats/{$roomId}/messages/" . $sent->json('message.id'))->assertOk();

        $this->assertSame(0, ChatMessage::count());
        Storage::disk(MediaStorage::disk())->assertMissing($path);
    }

    public function test_deleting_account_removes_chats_and_their_images(): void
    {
        Storage::fake(MediaStorage::disk());

        [$mom, $son] = $this->family();

        $roomId = $this->openChat($son, $mom);

        $this->post("/api/chats/{$roomId}/messages", [
            'image' => $this->fakePng(),
        ], ['Accept' => 'application/json'])->assertCreated();

        $path = ChatMessage::first()->image_path;

        app(AccountDeletionService::class)->delete($son->fresh());

        $this->assertSame(0, Conversation::count());
        $this->assertSame(0, ChatMessage::count());
        Storage::disk(MediaStorage::disk())->assertMissing($path);
    }

    // =====================================================
    // แจ้งเตือนเด้ง
    // =====================================================

    private function fakeFcm(): void
    {
        $this->withoutDefer();

        Http::preventStrayRequests();

        config(['services.fcm.credentials' => base64_encode(json_encode([
            'project_id' => 'test-project',
            'client_email' => 'push@test-project.iam.gserviceaccount.com',
            'private_key' => 'unused',
        ]))]);

        Cache::put('fcm.access_token.test-project', 'cached-access-token', 600);

        Http::fake([self::FCM_URL => Http::response(['name' => 'ok'])]);
    }

    public function test_new_message_is_pushed_but_not_listed_in_notifications(): void
    {
        $this->fakeFcm();

        [$mom, $son] = $this->family();

        DeviceToken::create([
            'user_id' => $son->id,
            'access_token_id' => $son->createToken('app')->accessToken->id,
            'token' => 'son-phone',
        ]);

        $roomId = $this->openChat($mom, $son);

        $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'กลับบ้านกี่โมง'])->assertCreated();

        Http::assertSent(function (Request $request) use ($roomId) {
            $message = $request['message'];

            return $message['fid'] === 'son-phone'
                && $message['notification']['title'] === 'Mom'
                && $message['notification']['body'] === 'กลับบ้านกี่โมง'
                && $message['data'] === [
                    'type' => 'new_message',
                    'conversation_id' => (string) $roomId,
                ]
                && $message['android']['notification']['tag'] === 'chat-' . $roomId;
        });

        $this->assertSame(0, AppNotification::count());
    }

    public function test_chat_push_can_be_turned_off(): void
    {
        $this->fakeFcm();

        [$mom, $son] = $this->family();

        $son->notification_settings = ['new_message' => false];
        $son->save();

        DeviceToken::create([
            'user_id' => $son->id,
            'access_token_id' => $son->createToken('app')->accessToken->id,
            'token' => 'son-phone',
        ]);

        $roomId = $this->openChat($mom, $son);

        $this->postJson("/api/chats/{$roomId}/messages", ['body' => 'hi'])->assertCreated();

        Http::assertNothingSent();

        // ตั้งค่าแสดงสวิตช์ข้อความแชท
        Sanctum::actingAs($son);

        $this->getJson('/api/settings')
            ->assertOk()
            ->assertJsonPath('settings.notifications.new_message', false);
    }
}
