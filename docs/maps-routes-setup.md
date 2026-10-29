# เปิดใช้ระยะทางและเวลาเดินทางตามถนน (Google Routes API)

ถ้ายังไม่ได้ตั้งค่า แอปยังใช้งานได้ตามปกติ แต่จะแสดง **ระยะทางเส้นตรง** แทน
ปุ่ม "เริ่มนำทาง" ยังเปิด Google Maps นำทางได้เหมือนเดิม

## ค่าใช้จ่าย

- ใช้ **Routes API แบบพื้นฐาน** (ไม่คิดสภาพจราจร) ซึ่งมีโควตาฟรีต่อเดือน
  ตรวจราคาและโควตาล่าสุดที่หน้า Google Maps Platform Pricing ก่อนเปิดใช้
- แอปช่วยประหยัดโควตาไว้แล้ว:
  - เรียกเฉพาะตอนที่ผู้ใช้เปิดดูสมาชิกบนแผนที่
  - ผลเดิมเก็บไว้ 10 นาที (เปิดดูซ้ำไม่เสียโควตา)
  - จำกัดคนละ 10 ครั้ง/นาที และ 200 ครั้ง/วัน
- แนะนำตั้ง **Budget alert** ใน Google Cloud → Billing → Budgets & alerts (เช่น เตือนที่ 100 บาท)

## STEP 1 — เปิด Routes API

1. เข้า Google Cloud Console แล้วเลือก **โปรเจกต์เดียวกับที่ใช้ Maps SDK for Android** ของแอป
2. APIs & Services → Library → ค้นหา **Routes API** → กด **Enable**

## STEP 2 — สร้าง API key สำหรับ Server

1. APIs & Services → Credentials → **Create credentials** → API key
2. ตั้งชื่อ เช่น `klaikan-server-routes`
3. Application restrictions → **None** (Server เรียกจาก Laravel Cloud ไม่มี IP คงที่)
4. API restrictions → **Restrict key** → เลือกเฉพาะ **Routes API** → Save
5. คัดลอก key ไว้ (**ห้ามส่งในแชต** และห้ามใส่ในโค้ด)

> อย่าใช้ key เดียวกับในแอป (key ในแอปล็อกไว้เฉพาะแอป Android และ Maps SDK)

## STEP 3 — ใส่ key ใน Laravel Cloud

1. Laravel Cloud → Environment ของ production → Custom environment variables
2. เพิ่ม `GOOGLE_MAPS_SERVER_KEY` = key จาก STEP 2
3. Save แล้ว **Deploy** ใหม่

## STEP 4 — ตรวจ

เปิดแอป → แท็บตำแหน่ง → แตะสมาชิก

- ขึ้น **"ระยะทางตามถนน"** และ **เวลาเดินทาง** พร้อมเส้นทางสีม่วงบนแผนที่ = ใช้ได้แล้ว
- ยังขึ้น "ระยะทางเส้นตรง" = ตรวจว่า Deploy แล้ว และเปิด Routes API ในโปรเจกต์เดียวกับ key
