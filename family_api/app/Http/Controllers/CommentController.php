<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\Comment;
use App\Models\CommentReport;
use App\Models\FamilyMember;
use App\Models\Interaction;
use App\Models\Post;
use App\Models\UserBlock;
use App\Support\MediaStorage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Throwable;

class CommentController extends Controller
{
    // ไฟล์แนบในความคิดเห็น
    private const MAX_IMAGE_KB = 10240;
    private const MAX_VIDEO_KB = 20480;

    // =====================================================
    // สร้าง Comment
    // =====================================================

    public function store(
        Request $request,
        Post $post
    ) {
        $request->validate([
            'content' => 'required_without:media|nullable|string|max:2000',
            // รูป / GIF (≤ 10 MB) หรือวิดีโอ (≤ 20 MB) 1 ไฟล์
            'media' => 'nullable|file|max:' . self::MAX_VIDEO_KB
                . '|mimetypes:image/jpeg,image/png,image/webp,image/gif,video/mp4,video/quicktime,video/3gpp',
            'media_thumbnail' => 'nullable|image|mimes:jpg,jpeg,png,webp|max:2048',
            'media_width' => 'nullable|integer|min:0|max:10000',
            'media_height' => 'nullable|integer|min:0|max:10000',
        ], [
            'content.required_without' => 'กรุณาพิมพ์ความคิดเห็น หรือแนบรูป/วิดีโอ',
            'media.mimetypes' => 'แนบได้เฉพาะรูป JPG, PNG, WEBP, GIF หรือวิดีโอ MP4',
            'media.max' => 'ไฟล์ใหญ่เกินไป (รูปไม่เกิน 10 MB วิดีโอไม่เกิน 20 MB)',
            'media.uploaded' => 'อัปโหลดไฟล์ไม่สำเร็จ กรุณาลองอีกครั้ง',
        ]);

        $media = $request->file('media');

        $mediaType = null;

        if ($media) {
            $mime = (string) $media->getMimeType();

            $mediaType = str_starts_with($mime, 'video/')
                ? Comment::MEDIA_VIDEO
                : ($mime === 'image/gif' ? Comment::MEDIA_GIF : Comment::MEDIA_IMAGE);

            if ($mediaType !== Comment::MEDIA_VIDEO && $media->getSize() > self::MAX_IMAGE_KB * 1024) {
                return response()->json([
                    'status' => false,
                    'message' => 'รูปหรือ GIF ต้องมีขนาดไม่เกิน 10 MB',
                    'errors' => ['media' => ['รูปหรือ GIF ต้องมีขนาดไม่เกิน 10 MB']],
                ], 422);
            }
        }

        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        // ยังไม่มีครอบครัว: แสดงความคิดเห็นได้เฉพาะโพสต์ชุมชน
        if (!$membership && !$post->isCommunity()) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณยังไม่ได้อยู่ในครอบครัว',
            ], 403);
        }

        if ($post->isCommunity()) {
            // โพสต์ชุมชน: ทุกคนแสดงความคิดเห็นได้ ยกเว้นโพสต์ที่ถูกซ่อน
            if ($post->hidden_at !== null) {
                return response()->json([
                    'status' => false,
                    'message' =>
                        'โพสต์นี้ถูกซ่อนแล้ว',
                ], 403);
            }
        } elseif (
            // โพสต์ครอบครัว: ต้องอยู่ Family เดียวกับ User
            $post->family_id !==
            $membership->family_id
        ) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณไม่มีสิทธิ์แสดงความคิดเห็นในโพสต์นี้',
            ], 403);
        }

        // เจ้าของโพสต์บล็อกเราไว้ → ไม่ต้องแจ้งเตือน
        $blockedByOwner = UserBlock::where(
            'user_id',
            $post->user_id
        )
            ->where(
                'blocked_user_id',
                $user->id
            )
            ->exists();

        // เก็บไฟล์ก่อน ถ้าบันทึกความคิดเห็นไม่สำเร็จค่อยลบทิ้ง
        $mediaPaths = [];

        if ($media) {
            $disk = MediaStorage::disk();

            $mediaPaths['media_path'] = $media->store('comment_media/' . $user->id, $disk);

            if ($mediaType === Comment::MEDIA_VIDEO && $request->hasFile('media_thumbnail')) {
                $mediaPaths['media_thumbnail_path'] = $request->file('media_thumbnail')
                    ->store('comment_media/' . $user->id . '/thumbnails', $disk);
            }

            if (in_array(false, $mediaPaths, true)) {
                MediaStorage::delete(array_filter($mediaPaths));

                return response()->json([
                    'status' => false,
                    'message' => 'อัปโหลดไฟล์ไม่สำเร็จ กรุณาลองอีกครั้ง',
                ], 422);
            }
        }

        try {
            $comment = DB::transaction(
                function () use (
                    $request,
                    $post,
                    $user,
                    $membership,
                    $blockedByOwner,
                    $mediaType,
                    $mediaPaths
                ) {
                    $comment = Comment::create([
                        'post_id' => $post->id,
                        'user_id' => $user->id,
                        'content' => filled($request->content) ? trim($request->content) : null,
                        'media_type' => $mediaType,
                        'media_path' => $mediaPaths['media_path'] ?? null,
                        'media_thumbnail_path' => $mediaPaths['media_thumbnail_path'] ?? null,
                        'media_width' => $mediaType ? $request->integer('media_width') ?: null : null,
                        'media_height' => $mediaType ? $request->integer('media_height') ?: null : null,
                    ]);

                    Interaction::record($user, Interaction::COMMENT, $post, meta: [
                        'comment_id' => $comment->id,
                        'excerpt' => $comment->excerpt(),
                    ]);

                    // ไม่แจ้งตัวเอง
                    if (
                        $post->user_id !==
                        $user->id
                        && !$blockedByOwner
                    ) {
                        AppNotification::create([
                            'user_id' =>
                                $post->user_id,

                            // โพสต์ชุมชนไม่ผูกกับครอบครัวของผู้แสดงความคิดเห็น
                            'family_id' =>
                                $post->isCommunity()
                                    ? null
                                    : $membership->family_id,
                            'type' => 'new_comment',
                            'title' =>
                                'ความคิดเห็นใหม่',
                            'message' =>
                                $user->name .
                                ' แสดงความคิดเห็นในโพสต์ของคุณ',
                            'data' => [
                                'post_id' =>
                                    $post->id,
                                'comment_id' =>
                                    $comment->id,
                            ],
                            'is_read' => false,
                        ]);
                    }

                    return $comment;
                }
            );
        } catch (Throwable $e) {
            MediaStorage::delete(array_values($mediaPaths));

            throw $e;
        }

        $comment->load(
            'user:id,name,profile_photo'
        );

        return response()->json([
            'status' => true,
            'message' =>
                'แสดงความคิดเห็นสำเร็จ',
            'comment' => $comment,
        ], 201);
    }

    // =====================================================
    // ลบ Comment
    // =====================================================

    public function destroy(
        Request $request,
        Comment $comment
    ) {
        $user = $request->user();

        // ต้องเป็นเจ้าของ Comment
        if (
            $comment->user_id !==
            $user->id
        ) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณสามารถลบได้เฉพาะความคิดเห็นของตัวเอง',
            ], 403);
        }

        // หา Post ของ Comment
        $post = Post::find(
            $comment->post_id
        );

        if (!$post) {
            return response()->json([
                'status' => false,
                'message' =>
                    'ไม่พบโพสต์ของความคิดเห็นนี้',
            ], 404);
        }

        // โพสต์ครอบครัว: User ต้องยังอยู่ใน Family ของ Post
        // โพสต์ชุมชน: เจ้าของความคิดเห็นลบได้เสมอ
        $membership =
            FamilyMember::where(
                'user_id',
                $user->id
            )
                ->where(
                    'family_id',
                    $post->family_id
                )
                ->first();

        if (!$post->isCommunity() && !$membership) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณไม่ได้อยู่ในครอบครัวของความคิดเห็นนี้แล้ว',
            ], 403);
        }

        // ลบออกจากประวัติการใช้งานของคนเขียนด้วย
        Interaction::where('type', Interaction::COMMENT)
            ->where('meta->comment_id', $comment->id)
            ->delete();

        $comment->delete();

        return response()->json([
            'status' => true,
            'message' =>
                'ลบความคิดเห็นสำเร็จ',
        ]);
    }

    // =====================================================
    // รายงาน Comment (เฉพาะในโพสต์ชุมชน)
    // =====================================================

    public function report(
        Request $request,
        Comment $comment
    ) {
        $data = $request->validate([
            'reason' =>
                'required|in:spam,inappropriate,harassment,scam,other',
            'details' => 'nullable|string|max:1000',
        ]);

        $user = $request->user();


        if (!$comment->post?->isCommunity()) {
            return response()->json([
                'status' => false,
                'message' =>
                    'รายงานได้เฉพาะความคิดเห็นในโพสต์ชุมชน',
            ], 422);
        }

        if ((int) $comment->user_id === (int) $user->id) {
            return response()->json([
                'status' => false,
                'message' =>
                    'ไม่สามารถรายงานความคิดเห็นของตัวเองได้',
            ], 422);
        }

        // รายงานซ้ำไม่นับเพิ่ม
        CommentReport::firstOrCreate(
            [
                'comment_id' => $comment->id,
                'user_id' => $user->id,
            ],
            [
                'reason' => $data['reason'],
                'details' => $data['details'] ?? null,
            ]
        );

        // ซ่อนอัตโนมัติเมื่อถูกรายงานครบ
        if (
            $comment->hidden_at === null
            && $comment->reports()->count() >= config('community.auto_hide_reports')
        ) {
            $comment->hidden_at = now();
            $comment->save();
        }

        return response()->json([
            'status' => true,
            'message' =>
                'ขอบคุณที่รายงาน เราจะตรวจสอบความคิดเห็นนี้',
        ]);
    }
}