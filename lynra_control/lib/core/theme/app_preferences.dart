import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences._();
  static final AppPreferences instance = AppPreferences._();

  String languageCode = 'tr';
  bool get isDark => AppColors.isDark;
  bool get isTurkish => languageCode == 'tr';

  String tr(String english, String turkish) =>
      isTurkish ? turkish : english;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    languageCode = prefs.getString('languageCode') == 'en' ? 'en' : 'tr';
    AppColors.isDark = prefs.getBool('isDark') ?? true;
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    if (value != 'en' && value != 'tr') return;
    if (languageCode == value) return;
    languageCode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', value);
  }

  Future<void> setDark(bool value) async {
    if (AppColors.isDark == value) return;
    AppColors.isDark = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', value);
  }
}
