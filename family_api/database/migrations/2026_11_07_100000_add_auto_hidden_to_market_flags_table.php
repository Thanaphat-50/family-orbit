<?php

use App\Models\MarketFlag;
use App\Services\MarketScreening;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ตรวจพบคำต้องห้าม → ซ่อนสินค้า / ปิดร้านอัตโนมัติจนกว่าผู้ดูแลจะตรวจ
     * auto_hidden: ระบบซ่อนเอง (ผู้ดูแลกด "ไม่ผิดกฎ" → แสดงคืนให้)
     */
    public function up(): void
    {
        Schema::table('market_flags', function (Blueprint $table) {
            $table->boolean('auto_hidden')->default(false)->after('status');
        });

        // รายการที่ตรวจพบไว้ก่อนหน้า และยังไม่ได้ตรวจ → ซ่อนตอนนี้
        $screening = app(MarketScreening::class);

        MarketFlag::open()->with('flaggable')->each(function (MarketFlag $flag) use ($screening) {
            if ($flag->flaggable) {
                $screening->autoHide($flag, $flag->flaggable);
            }
        });
    }

    public function down(): void
    {
        Schema::table('market_flags', function (Blueprint $table) {
            $table->dropColumn('auto_hidden');
        });
    }
};
