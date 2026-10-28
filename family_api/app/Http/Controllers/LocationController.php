<?php

namespace App\Http\Controllers;

use App\Models\FamilyMember;
use App\Models\User;
use App\Models\UserLocation;
use Illuminate\Http\Request;

class LocationController extends Controller
{
    // =====================================================
    // อัปเดตตำแหน่งของตัวเอง
    // =====================================================

    public function update(Request $request)
    {
        $user = $request->user();

        // ต้องอยู่ใน Family ก่อน
        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        if (!$membership) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณต้องอยู่ในครอบครัวก่อนจึงจะอัปเดตตำแหน่งได้',
            ], 403);
        }

        $data = $request->validate([
            'latitude' =>
                'required|numeric|between:-90,90',

            'longitude' =>
                'required|numeric|between:-180,180',

            'accuracy' =>
                'nullable|numeric|min:0',
        ]);

        // ปิดการแชร์ตำแหน่งอยู่ → ไม่เก็บตำแหน่ง
        // (กันแอปเวอร์ชันเก่าที่ยังส่งตำแหน่งมา)
        if ($user->location_sharing === false) {
            return response()->json([
                'status' => true,
                'shared' => false,
                'message' =>
                    'คุณปิดการแชร์ตำแหน่งอยู่ ตำแหน่งจึงไม่ถูกบันทึก',
            ]);
        }

        $location = UserLocation::updateOrCreate(
            [
                'user_id' => $user->id,
            ],
            [
                'latitude' =>
                    $data['latitude'],

                'longitude' =>
                    $data['longitude'],

                'accuracy' =>
                    $data['accuracy'] ?? null,

                'last_seen_at' => now(),
            ]
        );

        return response()->json([
            'status' => true,
            'message' =>
                'อัปเดตตำแหน่งสำเร็จ',
            'location' => $location,
        ]);
    }

    // =====================================================
    // ดูตำแหน่งสมาชิกใน Family เดียวกัน
    // =====================================================

    public function familyLocations(
        Request $request
    ) {
        $user = $request->user();

        // หาว่า User อยู่ Family ไหน
        $membership = FamilyMember::where(
            'user_id',
            $user->id
        )->first();

        if (!$membership) {
            return response()->json([
                'status' => false,
                'message' =>
                    'คุณยังไม่ได้อยู่ในครอบครัว',
                'locations' => [],
            ], 403);
        }

        // เอาเฉพาะ User ID ที่ยังเป็นสมาชิก Family นี้จริง ๆ
        $memberIds = FamilyMember::where(
            'family_id',
            $membership->family_id
        )
            ->pluck('user_id');

        // สมาชิกที่ปิดการแชร์ตำแหน่ง (รวมตัวเราเอง)
        $pausedIds = User::whereIn('id', $memberIds)
            ->where('location_sharing', false)
            ->pluck('id');

        // ชื่อคนอื่นที่ปิดแชร์ (ให้ครอบครัวรู้ว่าทำไมไม่เห็นตำแหน่ง)
        // สถานะของตัวเองดูได้จาก /api/settings
        $paused = User::whereIn('id', $pausedIds)
            ->where('id', '!=', $user->id)
            ->get(['id', 'name']);

        // ดึง Location เฉพาะสมาชิกปัจจุบันที่เปิดแชร์อยู่เท่านั้น
        $locations = UserLocation::whereIn(
            'user_id',
            $memberIds->diff($pausedIds)
        )
            ->with([
                'user:id,name,email,profile_photo'
            ])
            ->get()
            // is_me → แอปรู้ว่าจุดไหนคือเรา (ไม่ต้องคิดระยะทาง/นำทางไปหาตัวเอง)
            ->each(fn (UserLocation $location) => $location->setAttribute(
                'is_me',
                (int) $location->user_id === (int) $user->id
            ))
            ->sortByDesc('is_me')
            ->values();

        return response()->json([
            'status' => true,
            'locations' => $locations,
            'paused' => $paused,
        ]);
    }
}