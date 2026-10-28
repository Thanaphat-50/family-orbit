<?php

namespace App\Http\Controllers;

use App\Models\FamilyMember;
use App\Models\Post;
use Illuminate\Http\Request;

// =======================================================
// ข้อความบนแผนที่
// โพสต์ครอบครัวของเรา → แสดงข้างตำแหน่งของเราบนแผนที่ 12 ชั่วโมง
// (ตั้งตอนโพสต์ได้ด้วย show_on_map ใน POST /api/posts)
// =======================================================

class MapStatusController extends Controller
{
    // POST /api/posts/{post}/map-status
    public function store(Request $request, Post $post)
    {
        if ($response = $this->denyUnlessOwner($request, $post)) {
            return $response;
        }

        if (!$post->canShowOnMap()) {
            return response()->json([
                'status' => false,
                'message' => 'แสดงบนแผนที่ได้เฉพาะโพสต์ครอบครัวที่มีข้อความ',
            ], 422);
        }

        $post->showOnMap();

        return response()->json([
            'status' => true,
            'message' => 'แสดงข้อความนี้บนแผนที่แล้ว ครอบครัวจะเห็นข้างตำแหน่งของคุณ '
                . Post::MAP_STATUS_HOURS . ' ชั่วโมง',
            'on_map' => true,
        ]);
    }

    // DELETE /api/posts/{post}/map-status
    public function destroy(Request $request, Post $post)
    {
        if ($response = $this->denyUnlessOwner($request, $post)) {
            return $response;
        }

        $post->map_status_until = null;
        $post->save();

        return response()->json([
            'status' => true,
            'message' => 'เอาข้อความออกจากแผนที่แล้ว',
            'on_map' => false,
        ]);
    }

    // ต้องเป็นเจ้าของโพสต์ และยังอยู่ในครอบครัวของโพสต์นี้
    private function denyUnlessOwner(Request $request, Post $post)
    {
        $user = $request->user();

        $member = (int) $post->user_id === (int) $user->id
            && FamilyMember::where('user_id', $user->id)
                ->where('family_id', $post->family_id)
                ->exists();

        if ($member) {
            return null;
        }

        return response()->json([
            'status' => false,
            'message' => 'ตั้งค่าได้เฉพาะโพสต์ครอบครัวของตัวเอง',
        ], 403);
    }
}
