import '../lib/core/control_engine.dart';
import '../lib/models/control_block.dart';
import '../lib/models/control_program.dart';

void expectOutput(ControlEngine engine, int index, bool expected, String label) {
  final actual = engine.output(index);
  if (actual != expected) {
    throw StateError('$label: Q$index expected $expected, got $actual');
  }
  print('PASS: $label');
}

ControlEngine sequence(RetriggerBehavior behavior) => ControlEngine(
  ControlProgram(name: 'Retrigger $behavior', controlBlocks: [
    ControlBlock(id: 'b1', groups: [
      ControlConditionGroup(
        id: 'r1',
        executionMode: RuleExecutionMode.triggered,
        retriggerBehavior: behavior,
        conditionLostBehavior: ConditionLostBehavior.continueRunning,
        conditions: [InputCondition(inputIndex: 1)],
        actions: [
          ControlAction.delay(durationMs: 5000),
          ControlAction.output(outputIndex: 1),
        ],
      ),
    ]),
  ]),
);

void testIgnore() {
  final engine = sequence(RetriggerBehavior.ignore);
  engine.scan(nowMs: 0, inputs: {1: false});
  engine.scan(nowMs: 100, inputs: {1: true}); // deadline = 5100
  engine.scan(nowMs: 200, inputs: {1: false});
  engine.scan(nowMs: 1000, inputs: {1: true}); // ignored
  engine.scan(nowMs: 5099, inputs: {1: true});
  expectOutput(engine, 1, false, 'Ignore: no output before original deadline');
  engine.scan(nowMs: 5100, inputs: {1: true});
  expectOutput(engine, 1, true, 'Ignore: original deadline retained');
}

void testRestart() {
  final engine = sequence(RetriggerBehavior.restart);
  engine.scan(nowMs: 0, inputs: {1: false});
  engine.scan(nowMs: 100, inputs: {1: true}); // original deadline = 5100
  engine.scan(nowMs: 200, inputs: {1: false});
  engine.scan(nowMs: 1000, inputs: {1: true}); // new deadline = 6000
  engine.scan(nowMs: 5100, inputs: {1: true});
  expectOutput(engine, 1, false, 'Restart: original deadline cancelled');
  engine.scan(nowMs: 5999, inputs: {1: true});
  expectOutput(engine, 1, false, 'Restart: still waiting before new deadline');
  engine.scan(nowMs: 6000, inputs: {1: true});
  expectOutput(engine, 1, true, 'Restart: output at new deadline');
}

void testPriority() {
  final engine = ControlEngine(ControlProgram(name: 'Priority', controlBlocks: [
    ControlBlock(id: 'b1', groups: [
      ControlConditionGroup(id: 'on', conditions: [InputCondition(inputIndex: 1)],
          actions: [ControlAction.output(outputIndex: 1, outputState: true)]),
      ControlConditionGroup(id: 'off', conditions: [InputCondition(inputIndex: 2)],
          actions: [ControlAction.output(outputIndex: 1, outputState: false)]),
    ]),
  ]));
  engine.scan(nowMs: 0, inputs: {1: false, 2: false});
  engine.scan(nowMs: 10, inputs: {1: true, 2: true});
  expectOutput(engine, 1, false, 'Priority: later matching OFF rule wins');
  engine.scan(nowMs: 20, inputs: {1: true, 2: false});
  expectOutput(engine, 1, true, 'Priority: later nonmatching rule does not block ON');
}

void main() {
  testIgnore();
  testRestart();
  testPriority();
  print('ALL BEHAVIOR TESTS PASSED');
}
