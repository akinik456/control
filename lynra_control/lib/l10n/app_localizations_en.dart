// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get newProgram => 'New Program';

  @override
  String get myPrograms => 'My Programs';

  @override
  String get programEditor => 'Program Editor';

  @override
  String get programName => 'Program name';

  @override
  String get defaultProgramName => 'Motor Control';

  @override
  String get programJson => 'Program JSON';

  @override
  String get close => 'Close';

  @override
  String get addStep => 'Add Step';

  @override
  String get inputCondition => 'Input condition';

  @override
  String get delayStep => 'Wait';

  @override
  String get outputControl => 'Output control';

  @override
  String get inputLabel => 'Input';

  @override
  String get conditionLabel => 'Condition';

  @override
  String get outputLabel => 'Output';

  @override
  String get risingEdge => 'When changing from OFF to ON';

  @override
  String get fallingEdge => 'When changing from ON to OFF';

  @override
  String get highLevel => 'While active';

  @override
  String get lowLevel => 'While inactive';

  @override
  String get delayDuration => 'Wait duration';

  @override
  String get secondsUnit => 'seconds';

  @override
  String get outputOn => 'Turn output ON';

  @override
  String get outputOff => 'Turn output OFF';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get deleteStep => 'Delete';
}
