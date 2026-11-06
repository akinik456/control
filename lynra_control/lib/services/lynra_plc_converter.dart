import 'dart:ffi';
import '../models/control_program.dart';
import '../models/control_block.dart';
import 'lynra_plc_ffi.dart';

class LynraPlcConverter {
  
static List<ControlConditionGroup> collectRules(
  ControlProgram program,
) {
  final rules = [
    for (final block in program.controlBlocks)
      ...block.groups,
  ];

  if (rules.length > 64) {
    throw StateError(
      'PLC supports maximum 64 rules. Found: ${rules.length}',
    );
  }

  return rules;
}

static void writeCondition(
  InputCondition source,
  LynraCondition target,
) {

if (source.inputIndex < 1 || source.inputIndex > 32) {
  throw RangeError(
    'Invalid PLC input index: ${source.inputIndex}. '
    'Valid range: 1..32',
  );
}

  target.inputIndex = source.inputIndex;

  switch (source.trigger) {
    case ConditionTrigger.highLevel:
      target.trigger = 0;
      break;
    case ConditionTrigger.lowLevel:
      target.trigger = 1;
      break;
    case ConditionTrigger.risingEdge:
      target.trigger = 2;
      break;
    case ConditionTrigger.fallingEdge:
      target.trigger = 3;
      break;
  }
}

static void writeAction(
  ControlAction source,
  LynraAction target,
) {

if (source.type != ControlActionType.delay &&
    (source.outputIndex < 1 || source.outputIndex > 32)) {
  throw RangeError(
    'Invalid PLC output index: ${source.outputIndex}. '
    'Valid range: 1..32',
  );
}

const maxDuration = 0xFFFFFFFF;

final durations = [
  source.durationMs,
  source.offDurationMs,
  source.onDelayMs,
  source.offDelayMs,
  source.onrDelayMs,
  source.blinkStartDelayMs,
  source.blinkCount,
];

if (durations.any((value) =>
    value < 0 || value > maxDuration)) {
  throw RangeError(
    'Invalid PLC action duration. '
    'Valid range: 0..$maxDuration ms',
  );
}

if (source.type == ControlActionType.blinkOutput &&
    (source.durationMs == 0 || source.offDurationMs == 0)) {
  throw RangeError(
    'FLASH ON and OFF durations must be greater than zero',
  );
}


  switch (source.type) {
    case ControlActionType.setOutput:
      target.type = 0;
      break;
    case ControlActionType.delay:
      target.type = 1;
      break;
    case ControlActionType.setLatch:
      target.type = 2;
      break;
    case ControlActionType.resetLatch:
      target.type = 3;
      break;
    case ControlActionType.toggleOutput:
      target.type = 4;
      break;
    case ControlActionType.blinkOutput:
      target.type = 5;
      break;
  }

  target.outputIndex = source.outputIndex;
  target.outputState = source.outputState;
  target.durationMs = source.durationMs;
  target.offDurationMs = source.offDurationMs;
  target.onDelayMs = source.onrDelayMs > 0 ? 0 : source.onDelayMs;
  target.offDelayMs = source.offDelayMs;
  target.onrDelayMs = source.onrDelayMs;
   target.blinkStartDelayMs = source.type == ControlActionType.blinkOutput ? source.blinkStartDelayMs : 0;
   target.blinkCount = source.type == ControlActionType.blinkOutput ? source.blinkCount : 0;
}

static void writeRule(
  ControlConditionGroup source,
  LynraRule target,
  int ruleId,
) {
  target.id = ruleId;

const maxDuration = 0xFFFFFFFF;

if (source.onDelayMs < 0 ||
    source.onDelayMs > maxDuration ||
    source.offDelayMs < 0 ||
    source.offDelayMs > maxDuration) {
  throw RangeError(
    'Invalid rule TON/TOF duration: ${source.id}',
  );
}

target.onDelayMs = source.onDelayMs;
target.offDelayMs = source.offDelayMs;

  switch (source.logicOperator) {
    case LogicOperator.and:
      target.logicOperator = 0;
      break;
    case LogicOperator.or:
      target.logicOperator = 1;
      break;
    case LogicOperator.xor:
      target.logicOperator = 2;
      break;
		case LogicOperator.andEdge:
			target.logicOperator = 3;
			break;
		case LogicOperator.nand:
			target.logicOperator = 4;
			break;
		case LogicOperator.nandEdge:
			target.logicOperator = 5;
			break;
		case LogicOperator.nor:
			target.logicOperator = 6;
			break;
		case LogicOperator.not:
			target.logicOperator = 7;
			break;	
  }

  switch (source.outputBehavior) {
    case OutputBehavior.followCondition:
      target.outputBehavior = 0;
      break;
    case OutputBehavior.latch:
      target.outputBehavior = 1;
      break;
  }

  switch (source.runPolicy) {
    case RuleRunPolicy.once:
      target.runPolicy = 0;
      break;
    case RuleRunPolicy.repeat:
      target.runPolicy = 1;
      break;
  }
	
if (source.conditions.length > 8) {
  throw StateError(
    'Rule ${source.id}: maximum 8 conditions supported',
  );
}

final conditionCount =
    source.logicOperator == LogicOperator.not
        ? (source.conditions.isEmpty ? 0 : 1)
        : source.conditions.length;

target.conditionCount = conditionCount;

for (var i = 0; i < conditionCount; i++) {
  writeCondition(source.conditions[i], target.conditions.elements[i]);
}

if (source.actions.length > 16) {
  throw StateError(
    'Rule ${source.id}: maximum 16 actions supported',
  );
}

target.actionCount = source.actions.length;

for (var i = 0; i < source.actions.length; i++) {
  writeAction(
    source.actions[i],
    target.actions.elements[i],
  );
}

}


}
