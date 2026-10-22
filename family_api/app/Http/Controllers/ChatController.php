<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Models\FamilyMember;
use App\Models\User;
use App\Models\UserBlock;
use App\Services\PushNotifications;
use App\Support\MediaStorage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Throwable;

use function Illuminate\Support\defer;

// =======================================================
// แชทส่วนตัว (เฉพาะคนในครอบครัวเดียวกัน)
// - ส่งข้อความ / รูปได้ ยกเลิกการส่งข้อความของตัวเองได้
// - ออกจากครอบครัวแล้ว: อ่านแชทเก่าได้ แต่ส่งต่อไม่ได้
// - แอปดึงข้อความใหม่เป็นระยะขณะเปิดห้องแชท + แจ้งเตือนเด้ง
// =======================================================

class ChatController extends Controller
{
    private const PAGE_SIZE = 30;

    private const MAX_IMAGE_KB = 4096;

    // =====================================================
    // GET /api/chats
    // ห้องแชทของเรา + รายชื่อคนในครอบครัว (เริ่มแชทใหม่)
    // =====================================================

    public function index(Request $request)
    {
        $me = $request->user();

        $familyIds = $this->familyMemberIds($me);

        $conversations = Conversation::of($me->id)
            ->whereNotNull('last_message_at')
            ->orderByDesc('last_message_at')
            ->get();

        // toBase(): ยังไม่มีห้องเลย → Eloquent Collection ว่าง merge ตัวเลขไม่ได้
        $otherIds = $conversations->toBase()
            ->map(fn (Conversation $conversation) => $conversation->otherUserId($me->id))
            ->merge($familyIds)
            ->unique()
            ->values();

        $users = User::whereIn('id', $otherIds)
            ->get(['id', 'name', 'profile_photo'])
            ->keyBy('id');

        $lastMessages = ChatMessage::whereIn(
            'id',
            ChatMessage::whereIn('conversation_id', $conversations->pluck('id'))
                ->selectRaw('max(id)')
                ->groupBy('conversation_id')
        )->get()->keyBy('conversation_id');

        $blockedIds = $this->blockedEitherWay($me);

        $rooms = $conversations->map(function (Conversation $conversation) use ($me, $users, $lastMessages, $familyIds, $blockedIds) {
            $otherId = $conversation->otherUserId($me->id);

            $last = $lastMessages->get($conversation->id);

            return [
                'id' => $conversation->id,
                'user' => $this->userPayload($users->get($otherId), $otherId),
                'last_message' => $last ? [
                    'body' => $last->body ? Str::limit($last->body, 80) : null,
                    'has_image' => $last->image_path !== null,
                    'is_mine' => (int) $last->sender_id === (int) $me->id,
                    'created_at' => $last->created_at?->toIso8601String(),
                ] : null,
                'unread_count' => $conversation->unreadCountFor($me->id),
                'can_send' => $familyIds->contains($otherId) && !$blockedIds->contains($otherId),
            ];
        })->values();

        $roomByUser = $conversations->mapWithKeys(
            fn (Conversation $conversation) => [$conversation->otherUserId($me->id) => $conversation->id]
        );

        $contacts = $familyIds
            ->map(fn ($id) => [
                ...$this->userPayload($users->get($id), (int) $id),
                'conversation_id' => $roomByUser->get($id),
            ])
            ->values();

        return response()->json([
            'status' => true,
            'conversations' => $rooms,
            'contacts' => $contacts,
        ]);
    }

    // =====================================================
    // GET /api/chats/unread-count (ตัวเลขบนไอคอนแชท)
    // =====================================================

    public function unreadCount(Request $request)
    {
        $me = $request->user();

        $count = ChatMessage::query()
            ->join('conversations', 'conversations.id', '=', 'chat_messages.conversation_id')
            ->where('chat_messages.sender_id', '!=', $me->id)
            ->where(function ($rooms) use ($me) {
                $rooms->where(function ($one) use ($me) {
                    $one->where('conversations.user_one_id', $me->id)
                        ->whereRaw('chat_messages.id > coalesce(conversations.user_one_read_id, 0)');
                })->orWhere(function ($two) use ($me) {
                    $two->where('conversations.user_two_id', $me->id)
                        ->whereRaw('chat_messages.id > coalesce(conversations.user_two_read_id, 0)');
                });
            })
            ->count();

        return response()->json([
            'status' => true,
            'unread_count' => $count,
        ]);
    }

    // =====================================================
    // POST /api/chats {user_id} → เปิดห้องแชทกับคนนี้
    // =====================================================

    public function open(Request $request)
    {
        $data = $request->validate([
            'user_id' => 'required|integer',
        ]);

        $me = $request->user();

        $otherId = (int) $data['user_id'];

        if ($otherId === (int) $me->id) {
            return response()->json([
                'status' => false,
                'message' => 'แชทกับตัวเองไม่ได้',
            ], 422);
        }

        if (!$this->familyMemberIds($me)->contains($otherId)) {
            return $this->onlyFamily();
        }

        $conversation = Conversation::between($me->id, $otherId);

        return response()->json([
            'status' => true,
            'conversation' => $this->conversationPayload($conversation, $me),
        ]);
    }

    // =====================================================
    // GET /api/chats/{conversation}/messages
    // ?after_id=N  ข้อความใหม่กว่า N (ดึงเป็นระยะ)
    // ?before_id=N ข้อความเก่ากว่า N (เลื่อนดูย้อนหลัง)
    // ไม่ส่ง = ข้อความล่าสุด
    // =====================================================

    public function messages(Request $request, Conversation $conversation)
    {
        $me = $request->user();

        if (!$conversation->hasMember($me->id)) {
            return $this->notFound();
        }

        $data = $request->validate([
            'after_id' => 'nullable|integer',
            'before_id' => 'nullable|integer',
        ]);

        $query = $conversation->messages();

        $hasMore = false;

        if (isset($data['after_id'])) {
            $messages = $query->where('id', '>', $data['after_id'])
                ->orderBy('id')
                ->limit(100)
                ->get();
        } else {
            $messages = $query
                ->when(isset($data['before_id']), fn ($older) => $older->where('id', '<', $data['before_id']))
                ->orderByDesc('id')
                ->limit(self::PAGE_SIZE + 1)
                ->get();

            $hasMore = $messages->count() > self::PAGE_SIZE;

            $messages = $messages->take(self::PAGE_SIZE)->reverse()->values();
        }

        // เปิดดูห้องอยู่ → นับว่าอ่านถึงข้อความล่าสุดแล้ว
        if (!isset($data['before_id'])) {
            $latestId = (int) $conversation->messages()->max('id');

            if ($latestId > $conversation->lastReadId($me->id)) {
                $conversation->forceFill([$conversation->readColumn($me->id) => $latestId])->save();
            }
        }

        return response()->json([
            'status' => true,
            'conversation' => $this->conversationPayload($conversation, $me),
            'messages' => $messages->map(fn (ChatMessage $message) => $this->messagePayload($message, $me))->values(),
            'has_more' => $hasMore,
        ]);
    }

    // =====================================================
    // POST /api/chats/{conversation}/messages
    // body (ข้อความ) และ/หรือ image (รูป 1 รูป แบบ multipart)
    // =====================================================

    public function send(Request $request, Conversation $conversation)
    {
        $me = $request->user();

        if (!$conversation->hasMember($me->id)) {
            return $this->notFound();
        }

        $data = $request->validate([
            'body' => 'required_without:image|nullable|string|max:2000',
            'image' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:' . self::MAX_IMAGE_KB,
        ], [
            'body.required_without' => 'กรุณาพิมพ์ข้อความหรือแนบรูป',
            'image.image' => 'รองรับเฉพาะรูป JPG, PNG หรือ WEBP',
            'image.mimes' => 'รองรับเฉพาะรูป JPG, PNG หรือ WEBP',
            'image.max' => 'รูปต้องมีขนาดไม่เกิน 4 MB',
        ]);

        $otherId = $conversation->otherUserId($me->id);

        if (!$this->canSend($me, $otherId)) {
            return $this->onlyFamily();
        }

        $body = isset($data['body']) ? trim($data['body']) : null;

        if (($body === null || $body === '') && !$request->hasFile('image')) {
            return response()->json([
                'status' => false,
                'message' => 'กรุณาพิมพ์ข้อความหรือแนบรูป',
            ], 422);
        }

        $imagePath = $request->hasFile('image')
            ? MediaStorage::storeAll([$request->file('image')], 'chat_images')[0]
            : null;

        try {
            $message = DB::transaction(function () use ($conversation, $me, $body, $imagePath) {
                $message = ChatMessage::create([
                    'conversation_id' => $conversation->id,
                    'sender_id' => $me->id,
                    'body' => $body === '' ? null : $body,
                    'image_path' => $imagePath,
                ]);

                // ข้อความของเราเอง = อ่านแล้ว
                $conversation->forceFill([
                    'last_message_at' => $message->created_at,
                    $conversation->readColumn($me->id) => $message->id,
                ])->save();

                return $message;
            });
        } catch (Throwable $e) {
            MediaStorage::delete([$imagePath]);

            throw $e;
        }

        $this->notifyRecipient($me, $otherId, $conversation, $message);

        return response()->json([
            'status' => true,
            'message' => $this->messagePayload($message, $me),
        ], 201);
    }

    // =====================================================
    // DELETE /api/chats/{conversation}/messages/{message}
    // ยกเลิกการส่ง (เฉพาะข้อความของตัวเอง)
    // =====================================================

    public function destroy(Request $request, Conversation $conversation, ChatMessage $message)
    {
        $me = $request->user();

        if (!$conversation->hasMember($me->id) || (int) $message->conversation_id !== (int) $conversation->id) {
            return $this->notFound();
        }

        if ((int) $message->sender_id !== (int) $me->id) {
            return response()->json([
                'status' => false,
                'message' => 'ยกเลิกได้เฉพาะข้อความของคุณ',
            ], 403);
        }

        $message->delete();

        return response()->json([
            'status' => true,
        ]);
    }

    // =====================================================
    // Helpers
    // =====================================================

    // คนในครอบครัวเดียวกับเรา (ไม่รวมตัวเอง)
    private function familyMemberIds(User $me)
    {
        $familyId = FamilyMember::where('user_id', $me->id)->value('family_id');

        if (!$familyId) {
            return collect();
        }

        return FamilyMember::where('family_id', $familyId)
            ->where('user_id', '!=', $me->id)
            ->pluck('user_id')
            ->map(fn ($id) => (int) $id);
    }

    // คนที่เราบล็อก หรือบล็อกเรา
    private function blockedEitherWay(User $me)
    {
        return UserBlock::where('user_id', $me->id)->pluck('blocked_user_id')
            ->merge(UserBlock::where('blocked_user_id', $me->id)->pluck('user_id'))
            ->map(fn ($id) => (int) $id)
            ->unique();
    }

    private function canSend(User $me, int $otherId): bool
    {
        return $this->familyMemberIds($me)->contains($otherId)
            && !$this->blockedEitherWay($me)->contains($otherId);
    }

    private function userPayload(?User $user, int $id): array
    {
        return [
            'id' => $id,
            'name' => $user?->name ?? 'ผู้ใช้',
            'profile_image_url' => $user?->profile_image_url,
        ];
    }

    private function conversationPayload(Conversation $conversation, User $me): array
    {
        $otherId = $conversation->otherUserId($me->id);

        return [
            'id' => $conversation->id,
            'user' => $this->userPayload(User::find($otherId, ['id', 'name', 'profile_photo']), $otherId),
            'can_send' => $this->canSend($me, $otherId),
            // อีกฝ่ายอ่านถึงข้อความไหนแล้ว (แสดง "อ่านแล้ว")
            'other_read_id' => $conversation->lastReadId($otherId),
        ];
    }

    private function messagePayload(ChatMessage $message, User $me): array
    {
        return [
            'id' => $message->id,
            'sender_id' => $message->sender_id,
            'is_mine' => (int) $message->sender_id === (int) $me->id,
            'body' => $message->body,
            'image_url' => $message->image_url,
            'created_at' => $message->created_at?->toIso8601String(),
        ];
    }

    // แจ้งเตือนเด้งหาอีกฝ่าย (ไม่บันทึกในหน้าแจ้งเตือน) หลังตอบแอปไปแล้ว
    private function notifyRecipient(User $me, int $otherId, Conversation $conversation, ChatMessage $message): void
    {
        $recipient = User::find($otherId, ['id', 'notification_settings']);

        if (!$recipient || !$recipient->wantsNotification(AppNotification::TYPE_NEW_MESSAGE)) {
            return;
        }

        $title = $me->name;

        $body = $message->body
            ? Str::limit($message->body, 100)
            : '📷 ส่งรูปภาพ';

        $conversationId = $conversation->id;

        defer(fn () => app(PushNotifications::class)->sendToUser(
            $otherId,
            $title,
            $body,
            [
                'type' => AppNotification::TYPE_NEW_MESSAGE,
                'conversation_id' => $conversationId,
            ],
            'chat-' . $conversationId
        ));
    }

    private function onlyFamily()
    {
        return response()->json([
            'status' => false,
            'message' => 'แชทได้เฉพาะคนในครอบครัวเดียวกัน',
        ], 403);
    }

    private function notFound()
    {
        return response()->json([
            'status' => false,
            'message' => 'ไม่พบห้องแชทนี้',
        ], 404);
    }
}
