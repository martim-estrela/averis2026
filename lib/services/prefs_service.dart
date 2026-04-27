import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static Future<bool> isOnboardingDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('onboarding_done') ?? false;
  }

  static Future<void> setOnboardingDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarding_done', true);
  }

  static Future<bool> isSetupDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('setup_done') ?? false;
  }

  static Future<void> setSetupDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('setup_done', true);
  }
}
