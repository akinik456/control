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
if (source.type == ControlActionType.thresholdTrigger) {
  if (source.thresholdInputIndex < 1 ||
      source.thresholdInputIndex > 32) {
    throw RangeError('Threshold Fre input must be 1..32');
  }

  if (source.thresholdGateMs < 1000 ||
      source.thresholdGateMs > 100000 ||
      source.thresholdGateMs % 1000 != 0) {
    throw RangeError('Threshold gate must be 1..100 seconds');
  }

  if (source.thresholdOn < 0 ||
      source.thresholdOn > 9999 ||
      source.thresholdOff < 0 ||
      source.thresholdOff > 9999) {
    throw RangeError('Threshold On/Off must be 0..9999');
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
			ControlActionType.thresholdTrigger => 13,
      _ => throw UnsupportedError('Unsupported timer: ${source.type.name}'),
    };
    target.outputIndex = source.outputIndex;
    target.followInputIndex = 0;
    target.tMs = _u32(source.timerTMs, 'timerTMs');
    target.thMs = _u32(source.timerTHMs, 'timerTHMs');
    target.tlMs = _u32(source.timerTLMs, 'timerTLMs');
    target.warningBeforeMs = _u32(source.timerWarningBeforeMs, 'timerWarningBeforeMs');
    target.warningOffMs = _u32(source.timerWarningOffMs, 'timerWarningOffMs');
    if (source.timerN < 0 || source.timerN > 255) {
      throw RangeError('timerN must be 0..255');
    }
    target.n = source.timerN;
    target.thRandom = (source.type == ControlActionType.onOffDelay || source.type == ControlActionType.edgeWipingRelay) && source.timerTHRandom ? 1 : 0;
    target.tlRandom = (source.type == ControlActionType.onOffDelay || source.type == ControlActionType.edgeWipingRelay) && source.timerTLRandom ? 1 : 0;
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
  source.type == ControlActionType.onOffDelay ||
  source.type == ControlActionType.retentiveOnDelay ||
  source.type == ControlActionType.edgeWipingRelay ||
  source.type == ControlActionType.stairwayTimer
) && source.timerRetrigger ? 1 : 0;

target.resetInputIndex =
    source.type == ControlActionType.onOffDelay ||
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
				
target.thresholdInputIndex =
    source.type == ControlActionType.thresholdTrigger
        ? source.thresholdInputIndex : 0;

target.thresholdGateMs =
    source.type == ControlActionType.thresholdTrigger
        ? source.thresholdGateMs : 0;

target.thresholdOn =
    source.type == ControlActionType.thresholdTrigger
        ? source.thresholdOn : 0;

target.thresholdOff =
    source.type == ControlActionType.thresholdTrigger
        ? source.thresholdOff : 0;

    target.virtualStart =
			const {
				ControlActionType.onOffDelay,
				ControlActionType.retentiveOnDelay,
				ControlActionType.wipingRelay,
				ControlActionType.edgeWipingRelay,
				ControlActionType.asynchronousPulse,
				ControlActionType.randomGenerator,
				ControlActionType.stopwatchTimer,
			}.contains(source.type) && source.virtualStart ? 1 : 0;
				
  }

  static void writeRule(ControlConditionGroup source, LynraRule target, int ruleId) {
		
    final conditionCount = source.conditionGroups.isNotEmpty
    ? source.conditionGroups.fold<int>(
        0,
        (sum, group) => sum + group.conditions.length,
      )
    : source.conditions.length;

if (conditionCount < 1 || conditionCount > 8) {
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
      LogicOperator.nand => 3,
      LogicOperator.nor => 4,
      LogicOperator.not => 5,
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

final conditions = source.conditionGroups.isNotEmpty
    ? source.conditionGroups
        .expand((group) => group.conditions)
        .toList()
    : source.conditions;

final count = conditions.length;

target.conditionCount = count;
    for (var i = 0; i < count; i++) {
      writeCondition(conditions[i], target.conditions.elements[i]);
    }
		
target.expressionCount = 0;

if (source.conditionGroups.isNotEmpty) {
  var tokenIndex = 0;
  var conditionIndex = 0;

  void addToken(int op, [int index = 0]) {
    if (tokenIndex >= 32) {
      throw StateError('RPN expression exceeds 32 tokens');
    }

    final token = target.expression.elements[tokenIndex++];
    token.op = op;
    token.conditionIndex = index;
  }

  void addOperator(LogicOperator op) {
    switch (op) {
      case LogicOperator.and:
        addToken(1);
      case LogicOperator.or:
        addToken(2);
      case LogicOperator.xor:
        addToken(3);
      case LogicOperator.nand:
        addToken(1);
        addToken(4);
      case LogicOperator.nor:
        addToken(2);
        addToken(4);
      case LogicOperator.not:
        throw UnsupportedError('NOT cannot be used between groups');
    }
  }

  for (var g = 0; g < source.conditionGroups.length; g++) {
    final group = source.conditionGroups[g];

    if (group.conditions.isEmpty) {
      throw StateError('Empty condition group');
    }

    for (var c = 0; c < group.conditions.length; c++) {
      addToken(0, conditionIndex++);

      if (c > 0) {
        final i = c - 1;
        final op = i < group.conditionOperators.length
            ? group.conditionOperators[i]
            : group.logicOperator;
        addOperator(op);
      }
    }

    if (group.negated) {
      addToken(4);
    }

    if (g > 0) {
      final i = g - 1;
      final op = i < source.groupOperators.length
          ? source.groupOperators[i]
          : source.groupsOperator;
      addOperator(op);
    }
  }

  target.expressionCount = tokenIndex;
}

if (source.conditionGroups.isEmpty &&
    count > 1 &&
    source.conditionOperators.isNotEmpty) {
  var tokenIndex = 0;

  void addToken(int op, [int conditionIndex = 0]) {
    final token = target.expression.elements[tokenIndex++];
    token.op = op;
    token.conditionIndex = conditionIndex;
  }

  // RPN: first condition
  addToken(0, 0);

  for (var i = 1; i < count; i++) {
    addToken(0, i);

    final opIndex = i - 1;
    final op = opIndex < source.conditionOperators.length
        ? source.conditionOperators[opIndex]
        : source.logicOperator;

    switch (op) {
      case LogicOperator.and:
        addToken(1);
      case LogicOperator.or:
        addToken(2);
      case LogicOperator.xor:
        addToken(3);
      case LogicOperator.nand:
        addToken(1);
        addToken(4);
      case LogicOperator.nor:
        addToken(2);
        addToken(4);
      case LogicOperator.not:
        throw UnsupportedError(
          'NOT cannot be used between conditions',
        );
    }
  }

  target.expressionCount = tokenIndex;
}

		for (final action in source.actions) {
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
