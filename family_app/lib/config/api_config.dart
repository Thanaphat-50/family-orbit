class ApiConfig {
  // ค่าเริ่มต้น = Laravel Cloud (Production)
  //
  // ทดสอบกับ Laravel ในเครื่องผ่าน Emulator:
  // flutter run --dart-define=API_SERVER_URL=http://10.0.2.2:8000
  static const String serverUrl = String.fromEnvironment(
    'API_SERVER_URL',
    defaultValue:
        'https://family-orbit-production-aznxgw.laravel.cloud',
  );

  static const String baseUrl =
      '$serverUrl/api';

  static String storageUrl(
    String path,
  ) {
    final cleanPath =
        path.startsWith('/')
            ? path.substring(1)
            : path;

    return '$serverUrl/storage/$cleanPath';
  }
}