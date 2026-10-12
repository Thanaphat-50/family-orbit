<?php

namespace App\Http\Controllers;

use App\Models\AppNotification;
use App\Models\FamilyMember;
use App\Models\Post;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PostController extends Controller
{
    // =====================================================
    // ดู Post ของครอบครัว
    // =====================================================

    public function index(Request $request)
    {
        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        if (!$membership) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่ได้อยู่ในครอบครัว',
                'posts' => [],
            ], 403);
        }

        $posts = Post::where(
            'family_id',
            $membership->family_id
        )
            ->with([
                'user:id,name,email,profile_photo',
                'comments.user:id,name,email,profile_photo',
            ])
            ->latest()
            ->get();

        return response()->json([
            'status' => true,
            'posts' => $posts,
        ]);
    }

    // =====================================================
    // สร้าง Post
    // =====================================================

    public function store(Request $request)
    {
        $request->validate([
            'content' => 'required|string|max:5000',
        ]);

        $user = $request->user();

        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        if (!$membership) {
            return response()->json([
                'status' => false,
                'message' => 'คุณยังไม่ได้อยู่ในครอบครัว',
            ], 403);
        }

        $post = DB::transaction(
            function () use (
                $request,
                $user,
                $membership
            ) {
                $post = Post::create([
                    'family_id' =>
                        $membership->family_id,
                    'user_id' => $user->id,
                    'content' => $request->content,
                ]);

                // แจ้งสมาชิกคนอื่นใน Family
                $memberIds =
                    FamilyMember::where(
                        'family_id',
                        $membership->family_id
                    )
                        ->where(
                            'user_id',
                            '!=',
                            $user->id
                        )
                        ->pluck('user_id');

                foreach ($memberIds as $memberId) {
                    AppNotification::create([
                        'user_id' => $memberId,
                        'family_id' =>
                            $membership->family_id,
                        'type' => 'new_post',
                        'title' => 'โพสต์ใหม่',
                        'message' =>
                            $user->name .
                            ' สร้างโพสต์ใหม่',
                        'data' => [
                            'post_id' => $post->id,
                        ],
                        'is_read' => false,
                    ]);
                }

                return $post;
            }
        );

        $post->load([
            'user:id,name,email,profile_photo',
            'comments.user:id,name,email,profile_photo',
        ]);

        return response()->json([
            'status' => true,
            'message' => 'สร้างโพสต์สำเร็จ',
            'post' => $post,
        ], 201);
    }

    // =====================================================
    // ลบ Post
    // =====================================================

    public function destroy(
        Request $request,
        Post $post
    ) {
        $user = $request->user();

        // ต้องเป็นเจ้าของ Post
        if ($post->user_id !== $user->id) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณสามารถลบได้เฉพาะโพสต์ของตัวเอง',
            ], 403);
        }

        // ต้องยังอยู่ใน Family ของ Post นี้
        $membership = FamilyMember::where(
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
                    'คุณไม่ได้อยู่ในครอบครัวของโพสต์นี้แล้ว',
            ], 403);
        }

        $post->delete();

        return response()->json([
            'status' => true,
            'message' => 'ลบโพสต์สำเร็จ',
        ]);
    }
}