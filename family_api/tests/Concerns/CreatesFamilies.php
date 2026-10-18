<?php

namespace Tests\Concerns;

use App\Models\Family;
use App\Models\FamilyMember;
use App\Models\User;

trait CreatesFamilies
{
    // =====================================================
    // สร้างครอบครัวพร้อมสมาชิก
    // =====================================================

    protected function createFamily(User $owner, array $members = []): Family
    {
        $family = Family::create([
            'name' => 'Family ' . $owner->id,
            'invite_code' => 'CODE' . $owner->id,
            'owner_id' => $owner->id,
        ]);

        FamilyMember::create([
            'family_id' => $family->id,
            'user_id' => $owner->id,
            'role' => 'owner',
        ]);

        foreach ($members as $member) {
            FamilyMember::create([
                'family_id' => $family->id,
                'user_id' => $member->id,
                'role' => 'member',
            ]);
        }

        return $family;
    }
}
