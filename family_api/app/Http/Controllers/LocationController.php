<?php

namespace App\Http\Controllers;

use App\Models\FamilyMember;
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

        // ดึง Location เฉพาะสมาชิกปัจจุบันเท่านั้น
        $locations = UserLocation::whereIn(
            'user_id',
            $memberIds
        )
            ->with([
                'user:id,name,email,profile_photo'
            ])
            ->get();

        return response()->json([
            'status' => true,
            'locations' => $locations,
        ]);
    }
}