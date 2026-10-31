import '../lib/core/control_engine.dart';
import '../lib/models/control_block.dart';
import '../lib/models/control_program.dart';

void main() {
  final rule = ControlConditionGroup(
    id: 'ton_1',
    onDelayMs: 5000,
    executionMode: RuleExecutionMode.continuous,
    outputBehavior: OutputBehavior.followCondition,
    conditions: [InputCondition(inputIndex: 1)],
    actions: [ControlAction.output(outputIndex: 1, outputState: true)],
  );
  final engine = ControlEngine(ControlProgram(
    name: 'TON test',
    controlBlocks: [ControlBlock(id: 'b1', groups: [rule])],
  ));

  void check(int ms, bool i1, bool expected, String description) {
    engine.scan(nowMs: ms, inputs: {1: i1});
    final actual = engine.output(1);
    if (actual != expected) {
      throw StateError('$description: t=$ms, I1=$i1, Q1=$actual, expected=$expected');
    }
    print('PASS: $description');
  }

  check(0, false, false, 'Initial OFF');
  check(100, true, false, 'Start timing');
  check(5099, true, false, 'Just before 5 seconds');
  check(5100, true, true, '5 seconds elapsed');
  check(5200, false, false, 'Immediate OFF');
  check(6000, true, false, 'Second start');
  check(8000, false, false, 'Interrupted before completion');
  check(8100, true, false, 'Restart from zero');
  check(13099, true, false, 'Old elapsed time not retained');
  check(13100, true, true, 'New 5-second interval elapsed');
  print('ALL TON TESTS PASSED');
}
