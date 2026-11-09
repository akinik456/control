import 'dart:ffi';
import '../models/control_program.dart';
import '../models/control_block.dart';
import 'lynra_plc_ffi.dart';
import 'package:flutter/foundation.dart';
/// Converter for LynraControl C Engine v1.0 (11 timer functions only).
class LynraPlcConverter {
  static List<ControlConditionGroup> collectRules(ControlProgram program) {
    final rules = [for (final block in program.controlBlocks) ...block.groups];
    if (rules.length > 64) {
      throw StateError('Maximum 64 rules supported; found ${rules.length}');
    }
    return rules;
  }

  static int _u32(int value, String field) {
    if (value < 0 || value > 0xFFFFFFFF) {
      throw RangeError('$field must be in 0..4294967295');
    }
    return value;
  }

  static void writeCondition(InputCondition source, LynraCondition target) {
    if (source.inputIndex < 1 || source.inputIndex > 32) {
      throw RangeError('Input index must be 1..32');
    }
    target.inputIndex = source.inputIndex;
    target.trigger = switch (source.trigger) {
      ConditionTrigger.highLevel => 0,
      ConditionTrigger.lowLevel => 1,
      ConditionTrigger.risingEdge => 2,
      ConditionTrigger.fallingEdge => 3,
    };
  }

  static void writeAction(ControlAction source, LynraAction target, {int resetInputIndex = 0}) {
	if (source.type == ControlActionType.upDownCounter) {
  final cnt = source.counterInputIndex;
  final dir = source.directionInputIndex;
  final reset = source.resetInputIndex;

  if (cnt < 1 || cnt > 32 ||
      dir < 0 || dir > 32 ||
      reset < 0 || reset > 32) {
    throw RangeError('Counter input indices must be 0..32; Cnt must be 1..32');
  }

  if ((dir != 0 && dir == cnt) ||
      (reset != 0 && (reset == cnt || reset == dir))) {
    throw StateError('Counter Cnt, Dir and RESET must use different inputs');
  }

  for (final value in [
    source.counterStartValue,
    source.counterOn,
    source.counterOff,
  ]) {
    if (value < -2147483648 || value > 2147483647) {
      throw RangeError('Counter values must fit int32');
    }
  }
}
if (source.type == ControlActionType.hoursCounter) {
  final en = source.hoursEnableInputIndex;
  final r = source.resetInputIndex;
  final ral = source.hoursResetAllInputIndex;

  if (en < 1 || en > 32 ||
      r < 0 || r > 32 ||
      ral < 0 || ral > 32) {
    throw RangeError('Hours Counter inputs must be 0..32; EN must be 1..32');
  }

  if ((r != 0 && r == en) ||
      (ral != 0 && (ral == en || ral == r))) {
    throw StateError('Hours Counter EN, R and Ral must use different inputs');
  }
debugPrint('CONVERTER HOURS TARGET: ${source.hoursTargetMs}');
  if (source.hoursTargetMs <= 0) {
    throw RangeError('Hours Counter target must be positive uint64');
  }
}
    if (!ControlAction.timerTypes.contains(source.type) &&
    !ControlAction.counterTypes.contains(source.type)) {
      throw UnsupportedError('Legacy action not supported by C Engine v1.0: ${source.type.name}');
    }
    if (source.outputIndex < 1 || source.outputIndex > 32) {
      throw RangeError('Output index must be 1..32');
    }
    target.type = switch (source.type) {
      ControlActionType.onDelay => 0,
      ControlActionType.offDelay => 1,
      ControlActionType.onOffDelay => 2,
      ControlActionType.retentiveOnDelay => 3,
      ControlActionType.wipingRelay => 4,
      ControlActionType.edgeWipingRelay => 5,
      ControlActionType.asynchronousPulse => 6,
      ControlActionType.randomGenerator => 7,
      ControlActionType.stairwayTimer => 8,
      ControlActionType.multipleFunctionTimer => 9,
      ControlActionType.stopwatchTimer => 10,
			ControlActionType.upDownCounter => 11,
			ControlActionType.hoursCounter => 12,
      _ => throw UnsupportedError('Unsupported timer: ${source.type.name}'),
    };
    target.outputIndex = source.outputIndex;
    target.tMs = _u32(source.timerTMs, 'timerTMs');
    target.thMs = _u32(source.timerTHMs, 'timerTHMs');
    target.tlMs = _u32(source.timerTLMs, 'timerTLMs');
    target.warningBeforeMs = _u32(source.timerWarningBeforeMs, 'timerWarningBeforeMs');
    target.warningOffMs = _u32(source.timerWarningOffMs, 'timerWarningOffMs');
    if (source.timerN < 0 || source.timerN > 255) {
      throw RangeError('timerN must be 0..255');
    }
    target.n = source.timerN;
    target.stopwatchTimeBase = switch (source.stopwatchTimeBase) {
      'milliseconds' => 0,
      'seconds' => 1,
      'minutes' => 2,
      _ => throw ArgumentError('Invalid stopwatch time base: ${source.stopwatchTimeBase}'),
    };
    final repeatable =
    source.type == ControlActionType.edgeWipingRelay;

target.repeat = repeatable && source.timerRepeat ? 1 : 0;
target.retrigger = (
  source.type == ControlActionType.retentiveOnDelay ||
  source.type == ControlActionType.edgeWipingRelay ||
  source.type == ControlActionType.stairwayTimer
) && source.timerRetrigger ? 1 : 0;

target.resetInputIndex =
		source.type == ControlActionType.upDownCounter ||
		source.type == ControlActionType.hoursCounter ||
    source.type == ControlActionType.stopwatchTimer ||
    source.type == ControlActionType.retentiveOnDelay ||
    (repeatable && source.timerRepeat)
        ? source.resetInputIndex
        : 0;
				
target.counterInputIndex =
    source.type == ControlActionType.upDownCounter
        ? source.counterInputIndex : 0;

target.directionInputIndex =
    source.type == ControlActionType.upDownCounter
        ? source.directionInputIndex : 0;

target.counterStartValue =
    source.type == ControlActionType.upDownCounter
        ? source.counterStartValue : 0;

target.counterOn =
    source.type == ControlActionType.upDownCounter
        ? source.counterOn : 0;

target.counterOff =
    source.type == ControlActionType.upDownCounter
        ? source.counterOff : 0;

target.hoursEnableInputIndex =
    source.type == ControlActionType.hoursCounter
        ? source.hoursEnableInputIndex : 0;

target.hoursResetAllInputIndex =
    source.type == ControlActionType.hoursCounter
        ? source.hoursResetAllInputIndex : 0;

target.hoursTargetMs =
    source.type == ControlActionType.hoursCounter
        ? source.hoursTargetMs : 0;				
				
  }

  static void writeRule(ControlConditionGroup source, LynraRule target, int ruleId) {
    if (source.conditions.isEmpty || source.conditions.length > 8) {
      throw StateError('Rule ${source.id}: 1..8 conditions required');
    }
    if (source.actions.isEmpty || source.actions.length > 16) {
      throw StateError('Rule ${source.id}: 1..16 actions required');
    }
    if (source.outputBehavior != OutputBehavior.followCondition ||
        source.onDelayMs != 0 || source.offDelayMs != 0) {
      throw UnsupportedError('Legacy rule output behavior / delays are not supported');
    }
    target.id = ruleId;
    target.logicOperator = switch (source.logicOperator) {
      LogicOperator.and => 0,
      LogicOperator.or => 1,
      LogicOperator.xor => 2,
      LogicOperator.andEdge => 3,
      LogicOperator.nand => 4,
      LogicOperator.nandEdge => 5,
      LogicOperator.nor => 6,
      LogicOperator.not => 7,
    };
    target.runPolicy = switch (source.runPolicy) {
      RuleRunPolicy.once => 0,
      RuleRunPolicy.repeat => 1,
    };

    final stopwatchActions = source.actions
    .where((a) => a.type == ControlActionType.stopwatchTimer)
    .toList();

if (stopwatchActions.isNotEmpty) {
  if (source.actions.length != 1 ||
      source.conditions.length != 1 ||
      source.conditions[0].trigger != ConditionTrigger.highLevel) {
    throw StateError(
        'Stopwatch requires one HIGH EN condition and one action');
  }

  final en = source.conditions[0].inputIndex;
  final reset = stopwatchActions.first.resetInputIndex;

  if (reset < 1 || reset > 32 || reset == en) {
    throw StateError('Stopwatch RESET must differ from EN');
  }

  if (stopwatchActions.first.timerTMs <= 0) {
    throw StateError('Stopwatch T must be greater than zero');
  }
}

final count = source.logicOperator == LogicOperator.not
    ? 1
    : source.conditions.length;

target.conditionCount = count;
    for (var i = 0; i < count; i++) {
      writeCondition(source.conditions[i], target.conditions.elements[i]);
    }for (final action in source.actions) {
  final repeatable =
      action.type == ControlActionType.edgeWipingRelay ||
      action.type == ControlActionType.stairwayTimer;

  if (repeatable && action.timerRepeat) {
    final reset = action.resetInputIndex;

    if (reset < 1 || reset > 32 ||
        source.conditions.any((c) => c.inputIndex == reset)) {
      throw StateError(
        'RESET must be a valid input different from trigger inputs',
      );
    }
  }
}
    target.actionCount = source.actions.length;
    for (var i = 0; i < source.actions.length; i++) {
      writeAction(source.actions[i], target.actions.elements[i]);
    }
  }
}
