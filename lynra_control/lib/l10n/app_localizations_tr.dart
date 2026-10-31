// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get newProgram => 'Yeni Program';

  @override
  String get myPrograms => 'Programlarım';

  @override
  String get programEditor => 'Program Editörü';

  @override
  String get programName => 'Program adı';

  @override
  String get defaultProgramName => 'Motor Kontrol';

  @override
  String get programJson => 'Program JSON';

  @override
  String get close => 'Kapat';

  @override
  String get addStep => 'İşlem Ekle';

  @override
  String get inputCondition => 'Giriş koşulu';

  @override
  String get delayStep => 'Bekle';

  @override
  String get outputControl => 'Çıkış kontrolü';

  @override
  String get inputLabel => 'Giriş';

  @override
  String get conditionLabel => 'Koşul';

  @override
  String get outputLabel => 'Çıkış';

  @override
  String get risingEdge => 'Pasiften aktife geçtiğinde';

  @override
  String get fallingEdge => 'Aktiften pasife geçtiğinde';

  @override
  String get highLevel => 'Aktif olduğu sürece';

  @override
  String get lowLevel => 'Pasif olduğu sürece';

  @override
  String get delayDuration => 'Bekleme süresi';

  @override
  String get secondsUnit => 'saniye';

  @override
  String get outputOn => 'Çıkışı aç (ON)';

  @override
  String get outputOff => 'Çıkışı kapat (OFF)';

  @override
  String get moveUp => 'Yukarı taşı';

  @override
  String get moveDown => 'Aşağı taşı';

  @override
  String get deleteStep => 'Sil';
}
