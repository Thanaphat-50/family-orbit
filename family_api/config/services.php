<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'token' => env('POSTMARK_TOKEN'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'resend' => [
        'key' => env('RESEND_KEY'),
    ],

    // เข้าสู่ระบบด้วย Google / LINE / Facebook (ดู App\Services\SocialIdentityVerifier)
    // ไม่ได้ตั้งค่า = ซ่อนปุ่มของเจ้านั้นในแอป

    // Web client ID ของ Google (คั่นด้วย , ได้หลายตัว)
    'google' => [
        'client_ids' => env('GOOGLE_CLIENT_IDS'),
    ],

    'line' => [
        'channel_id' => env('LINE_CHANNEL_ID'),
    ],

    'facebook' => [
        'app_id' => env('FACEBOOK_APP_ID'),
        'app_secret' => env('FACEBOOK_APP_SECRET'),
        // ว่าง = ใช้เวอร์ชัน Graph API ที่ตั้งไว้ในแอป Facebook
        'graph_version' => env('FACEBOOK_GRAPH_VERSION'),
    ],

    // แจ้งเตือนเด้ง (Firebase Cloud Messaging) ดู App\Services\PushNotifications
    'fcm' => [
        // ไฟล์ JSON ของ Service account ทั้งไฟล์ แปลงเป็น base64 (Laravel Cloud)
        'credentials' => env('FIREBASE_CREDENTIALS_BASE64'),

        // หรือ path ของไฟล์ JSON (ในเครื่อง)
        'credentials_path' => env('FIREBASE_CREDENTIALS_PATH'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

];
