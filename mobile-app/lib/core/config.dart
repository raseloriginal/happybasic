/// Build-time settings. Override the server with:
///   flutter build apk --dart-define=API_BASE=https://your-domain.com
class AppConfig {
  static const String defaultBase =
      String.fromEnvironment('API_BASE', defaultValue: 'https://v2.happybangladesh.com');

  static const String appName = 'হ্যাপি বাংলাদেশ';

  /// Map tiles (same providers as the web panels).
  static const String tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}
