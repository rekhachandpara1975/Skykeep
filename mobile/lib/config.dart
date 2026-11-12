/// Build-time configuration (pass with --dart-define).
class Config {
  static const appName = 'SkyKeep';
  static const shortCode = 'SK';
  static const supportEmail = 'help.skykeep@gmail.com';
  static const websiteUrl = String.fromEnvironment('WEBSITE_URL', defaultValue: 'https://skykeep.vercel.app');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Google Play build: never shows UPI, prices or the plans WebView.
  static const playStore = bool.fromEnvironment('PLAY_STORE');

  /// Set only for the ads APK, e.g. utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download.
  static const apkReferrer = String.fromEnvironment('APK_REFERRER');

  static const androidAppId = String.fromEnvironment('ANDROID_APP_ID',
      defaultValue: playStore ? 'com.skykeep.play' : 'com.skykeep.app');
  static String get authCallback => '$androidAppId://login-callback';

  static const jsChannel = '${appName}App';
  static const policyVersion = '2026-11';
}
