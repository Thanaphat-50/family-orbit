class ApiConfig {
  // IP ของคอมใน Wi-Fi วงเดียวกับมือถือ
  static const String serverUrl =
      'https://family-orbit-production-aznxgw.laravel.cloud';

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