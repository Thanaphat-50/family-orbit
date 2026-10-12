<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\Comment;
use App\Models\FamilyMember;
use App\Models\Post;
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

        // Post ต้องอยู่ Family เดียวกับ User
        if (
            $post->family_id !==
            $membership->family_id
        ) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณไม่มีสิทธิ์แสดงความคิดเห็นในโพสต์นี้',
            ], 403);
        }

        $comment = DB::transaction(
            function () use (
                $request,
                $post,
                $user,
                $membership
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
                ) {
                    AppNotification::create([
                        'user_id' =>
                            $post->user_id,
                        'family_id' =>
                            $membership->family_id,
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
            'user:id,name,email'
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

        // User ต้องยังอยู่ใน Family ของ Post
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

        if (!$membership) {
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