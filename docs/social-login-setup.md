# ตั้งค่าเข้าสู่ระบบด้วย Google / LINE / Facebook

ทั้ง 3 เจ้า **ฟรี** ไม่มีสัญญาต้องเซ็น
ตั้งค่าเสร็จแล้วใส่ค่าใน **Laravel Cloud → production → Settings → Custom environment variables** แล้ว Deploy
ปุ่มในแอปจะขึ้นเองเฉพาะเจ้าที่ตั้งค่าแล้ว (ไม่ต้องสร้างแอปใหม่)

ข้อมูลที่ใช้บ่อย:

| รายการ | ค่า |
|---|---|
| Package name | `com.familyorbit.app` |
| SHA-1 กุญแจอัปโหลด (แอปตัวจริง) | `F7:FB:65:58:D0:8E:6C:87:B2:EE:5D:F5:A6:4D:F8:3F:2A:CB:6B:26` |
| SHA-1 กุญแจทดสอบ (debug) | `6F:CA:30:04:08:A1:D2:67:3C:CB:F7:F5:EB:F7:91:75:C9:48:6B:CD` |
| นโยบายความเป็นส่วนตัว | `https://family-orbit-production-aznxgw.laravel.cloud/privacy` |
| ข้อกำหนดการใช้งาน | `https://family-orbit-production-aznxgw.laravel.cloud/terms` |
| วิธีลบข้อมูล | `https://family-orbit-production-aznxgw.laravel.cloud/account/delete` |
| Facebook Redirect URI | `https://family-orbit-production-aznxgw.laravel.cloud/auth/facebook/callback` |

> ⚠️ เมื่อขึ้น Play Store แล้ว ต้องเพิ่ม **SHA-1 ของ Play App Signing** (Play Console → Setup → App signing)
> ใน Firebase และ LINE ด้วย ไม่อย่างนั้นปุ่ม Google / LINE ใช้ไม่ได้ในแอปที่โหลดจาก Play Store

---

## 1. Google (ใช้โปรเจกต์ Firebase `klaikan` เดิม)

1. Firebase Console → โปรเจกต์ **klaikan** → **Build → Authentication** → **Get started**
2. แท็บ **Sign-in method** → **Google** → เปิด **Enable** → เลือก Support email → **Save**
3. กด **Google** อีกครั้ง → เปิด **Web SDK configuration** → คัดลอก **Web client ID**
   (ลงท้ายด้วย `.apps.googleusercontent.com`)
4. ⚙️ **Project settings** → **Your apps** → แอป Android `com.familyorbit.app` → **Add fingerprint**
   ใส่ SHA-1 ทั้ง 2 ค่าในตารางด้านบน (ทีละค่า)
5. Google Cloud Console (https://console.cloud.google.com) → เลือกโปรเจกต์ **klaikan** →
   **Google Auth Platform → Audience** → ถ้าสถานะเป็น **Testing** ให้กด **Publish app**
   (ขอแค่ชื่อ อีเมล รูป ไม่ต้องรอ Google ตรวจ)
6. Laravel Cloud → เพิ่ม `GOOGLE_CLIENT_IDS=<Web client ID>` → Save → Deploy

## 2. LINE

1. https://developers.line.biz → **Log in** ด้วยบัญชี LINE
2. **Create a new provider** → ชื่อ `ใกล้กัน`
3. **Create a LINE Login channel**
   - Region: Thailand / Channel name: `ใกล้กัน` / App types: **Mobile app**
   - ใส่อีเมล + ลิงก์นโยบายความเป็นส่วนตัว + ข้อกำหนด → ยอมรับข้อกำหนด → **Create**
4. แท็บ **LINE Login** → **Mobile app**
   - Package names: `com.familyorbit.app`
   - Package signatures (คนละบรรทัด ตัวพิมพ์เล็ก ไม่มี `:`):
     `f7fb6558d08e6c87b2ee5df5a64df83f2acb6b26`
     `6fca300408a1d2673ccbf7f5ebf79175c9486bcd`
5. แท็บ **Basic settings** → คัดลอก **Channel ID** (ตัวเลข)
   - (ไม่บังคับ) **OpenID Connect → Email address permission → Apply** ถ้าอยากได้อีเมลผู้ใช้
6. ด้านบนของช่อง สถานะ **Developing** → เปลี่ยนเป็น **Published** (ไม่อย่างนั้นใช้ได้เฉพาะผู้ดูแล)
7. Laravel Cloud → เพิ่ม `LINE_CHANNEL_ID=<Channel ID>` → Save → Deploy

## 3. Facebook

1. https://developers.facebook.com → **My Apps → Create app**
2. Use case: **Authenticate and request data from users with Facebook Login** → ตั้งชื่อ `ใกล้กัน` → Create
3. **Use cases → Customize** (Facebook Login)
   - **Permissions**: เพิ่ม **email** (public_profile มีอยู่แล้ว)
   - **Settings → Valid OAuth Redirect URIs**: ใส่ Facebook Redirect URI จากตารางด้านบน → Save
4. **App settings → Basic**
   - ใส่ Privacy Policy URL, Terms of Service URL, User data deletion → *Data deletion instructions URL*
     (ลิงก์ "วิธีลบข้อมูล"), App icon (1024×1024), Category → Save
   - คัดลอก **App ID** และ **App Secret** (กด Show)
   - ⚠️ **App Secret ห้ามส่งในแชต / ห้ามใส่ในโค้ด**
5. **Publish** แอป (Go live) ไม่อย่างนั้นใช้ได้เฉพาะผู้ดูแลแอป
6. Laravel Cloud → เพิ่ม
   `FACEBOOK_APP_ID=<App ID>`
   `FACEBOOK_APP_SECRET=<App Secret>`
   → Save → Deploy

---

## หลังตั้งค่า

- เปิดแอป → หน้าเข้าสู่ระบบจะมีปุ่มของเจ้าที่ตั้งค่าแล้ว
- คนที่มีบัญชีอยู่แล้ว: เข้าด้วยอีเมลเดิม → **ตั้งค่า → บัญชีที่เชื่อมต่อ** → เชื่อม Google / LINE / Facebook
- Google ที่อีเมลตรงกับบัญชีเดิม จะเข้าบัญชีเดิมให้อัตโนมัติ
  ส่วน LINE / Facebook ที่อีเมลซ้ำ ต้องเชื่อมจากหน้าตั้งค่า (กันคนอื่นสวมรอย)
- อัปเดตแบบฟอร์ม Data safety ใน Play Console ให้ตรง (ข้อมูลบัญชีจากผู้ให้บริการ)
