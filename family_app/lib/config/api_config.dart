class ApiConfig {
  // IP ของคอมใน Wi-Fi วงเดียวกับมือถือ
  static const String serverUrl =
      'http://192.168.0.106:8000';

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