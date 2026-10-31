import '../lib/core/control_engine.dart';
import '../lib/models/control_block.dart';
import '../lib/models/control_program.dart';

void check(ControlEngine e, bool expected, String name) {
  final actual = e.output(1);
  if (actual != expected) {
    throw StateError('$name: expected Q1=$expected, got $actual');
  }
  print('PASS: $name');
}

ControlEngine makeEngine({bool reverseOrder = false, int onDelayMs = 0}) {
  final setRule = ControlConditionGroup(
    id: 'set', onDelayMs: onDelayMs,
    conditions: [InputCondition(inputIndex: 1)],
    actions: [ControlAction.set(outputIndex: 1)],
  );
  final resetRule = ControlConditionGroup(
    id: 'reset',
    conditions: [InputCondition(inputIndex: 2)],
    actions: [ControlAction.reset(outputIndex: 1)],
  );
  return ControlEngine(ControlProgram(
    name: 'SET RESET test',
    controlBlocks: [ControlBlock(
      id: 'b1', groups: reverseOrder ? [resetRule, setRule] : [setRule, resetRule],
    )],
  ));
}

void testLatchAndPriority(bool reverseOrder) {
  final suffix = reverseOrder ? 'RESET first' : 'SET first';
  final e = makeEngine(reverseOrder: reverseOrder);
  e.scan(nowMs: 0, inputs: {1: false, 2: false});
  check(e, false, '$suffix: initially OFF');
  e.scan(nowMs: 10, inputs: {1: true, 2: false});
  check(e, true, '$suffix: SET activates');
  e.scan(nowMs: 20, inputs: {1: false, 2: false});
  check(e, true, '$suffix: SET remains latched');
  e.scan(nowMs: 30, inputs: {1: true, 2: true});
  check(e, false, '$suffix: simultaneous SET/RESET -> RESET');
  e.scan(nowMs: 40, inputs: {1: true, 2: false});
  check(e, false, '$suffix: releasing RESET does not auto-SET');
  e.scan(nowMs: 50, inputs: {1: false, 2: false});
  e.scan(nowMs: 60, inputs: {1: true, 2: false});
  check(e, true, '$suffix: new SET activation works');
  e.scan(nowMs: 70, inputs: {1: false, 2: true});
  check(e, false, '$suffix: RESET clears latch');
  e.scan(nowMs: 80, inputs: {1: false, 2: false});
  check(e, false, '$suffix: RESET stays latched');
}

void testDelayedSet() {
  final e = makeEngine(onDelayMs: 5000);
  e.scan(nowMs: 0, inputs: {1: false, 2: false});
  e.scan(nowMs: 100, inputs: {1: true, 2: false});
  e.scan(nowMs: 5099, inputs: {1: true, 2: false});
  check(e, false, 'TON+SET: before 5 seconds');
  e.scan(nowMs: 5100, inputs: {1: true, 2: false});
  check(e, true, 'TON+SET: after 5 seconds');
  e.scan(nowMs: 5200, inputs: {1: false, 2: false});
  check(e, true, 'TON+SET: remains ON after I1 OFF');
}

void main() {
  testLatchAndPriority(false);
  testLatchAndPriority(true);
  testDelayedSet();
  print('ALL SET/RESET TESTS PASSED');
}
