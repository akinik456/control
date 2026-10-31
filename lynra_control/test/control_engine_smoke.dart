import '../lib/core/control_engine.dart';
import '../lib/models/control_block.dart';
import '../lib/models/control_program.dart';

void check(bool actual, bool expected, String label) {
  if (actual != expected) {
    throw StateError('$label: expected $expected, got $actual');
  }
  print('PASS: $label');
}

ControlEngine makeEngine(ControlConditionGroup rule) => ControlEngine(
      ControlProgram(name: 'Smoke test', controlBlocks: [
        ControlBlock(id: 'block_1', groups: [rule]),
      ]),
    );

void main() {
  // 1: Continuous rule follows the input.
  final continuous = makeEngine(ControlConditionGroup(
    id: 'continuous',
    conditions: [InputCondition(inputIndex: 1)],
    actions: [ControlAction.output(outputIndex: 1)],
  ));
  continuous.scan(nowMs: 0, inputs: {1: false});
  check(continuous.output(1), false, 'Continuous: I1 OFF -> Q1 OFF');
  continuous.scan(nowMs: 10, inputs: {1: true});
  check(continuous.output(1), true, 'Continuous: I1 ON -> Q1 ON');
  continuous.scan(nowMs: 20, inputs: {1: false});
  check(continuous.output(1), false, 'Continuous: I1 OFF again -> Q1 OFF');

  // 2: Triggered sequence continues after the input goes OFF.
  final sequence = makeEngine(ControlConditionGroup(
    id: 'sequence',
    executionMode: RuleExecutionMode.triggered,
    conditionLostBehavior: ConditionLostBehavior.continueRunning,
    conditions: [InputCondition(inputIndex: 1)],
    actions: [
      ControlAction.output(outputIndex: 1),
      ControlAction.delay(durationMs: 5000),
      ControlAction.output(outputIndex: 2),
    ],
  ));
  sequence.scan(nowMs: 0, inputs: {1: false});
  sequence.scan(nowMs: 100, inputs: {1: true});
  check(sequence.output(1), true, 'Sequence: Q1 immediately ON');
  check(sequence.output(2), false, 'Sequence: Q2 initially OFF');
  sequence.scan(nowMs: 200, inputs: {1: false});
  sequence.scan(nowMs: 5099, inputs: {1: false});
  check(sequence.output(2), false, 'Sequence: Q2 OFF before deadline');
  sequence.scan(nowMs: 5100, inputs: {1: false});
  check(sequence.output(2), true, 'Sequence: Q2 ON at 5 seconds');

  // 3: A cancelled sequence must not finish its delayed action.
  final cancelled = makeEngine(ControlConditionGroup(
    id: 'cancel',
    executionMode: RuleExecutionMode.triggered,
    conditionLostBehavior: ConditionLostBehavior.cancel,
    conditions: [InputCondition(inputIndex: 1)],
    actions: [
      ControlAction.delay(durationMs: 5000),
      ControlAction.output(outputIndex: 1),
    ],
  ));
  cancelled.scan(nowMs: 0, inputs: {1: false});
  cancelled.scan(nowMs: 100, inputs: {1: true});
  cancelled.scan(nowMs: 200, inputs: {1: false});
  cancelled.scan(nowMs: 6000, inputs: {1: false});
  check(cancelled.output(1), false, 'Cancel: delayed output stays OFF');

  print('ALL SMOKE TESTS PASSED');
}
