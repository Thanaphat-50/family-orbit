<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\Comment;
use App\Models\FamilyMember;
use App\Models\Post;
use App\Models\UserBlock;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CommentController extends Controller
{
    // =====================================================
    // สร้าง Comment
    // =====================================================

    public function store(
        Request $request,
        Post $post
    ) {
        $request->validate([
            'content' => 'required|string|max:2000',
        ]);

        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        if (!$membership) {
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

        $comment = DB::transaction(
            function () use (
                $request,
                $post,
                $user,
                $membership,
                $blockedByOwner
            ) {
                $comment = Comment::create([
                    'post_id' => $post->id,
                    'user_id' => $user->id,
                    'content' =>
                        $request->content,
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

        $comment->delete();

        return response()->json([
            'status' => true,
            'message' =>
                'ลบความคิดเห็นสำเร็จ',
        ]);
    }
}