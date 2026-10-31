import '../lib/core/control_engine.dart';
import '../lib/models/control_block.dart';
import '../lib/models/control_program.dart';

void main() {
  void runCase(String name, int ton, int tof, List<(int, bool, bool)> steps) {
    final rule = ControlConditionGroup(
      id: 'timer', onDelayMs: ton, offDelayMs: tof,
      executionMode: RuleExecutionMode.continuous,
      outputBehavior: OutputBehavior.followCondition,
      conditions: [InputCondition(inputIndex: 1)],
      actions: [ControlAction.output(outputIndex: 1, outputState: true)],
    );
    final engine = ControlEngine(ControlProgram(
      name: name, controlBlocks: [ControlBlock(id: 'b', groups: [rule])],
    ));
    for (final (ms, input, expected) in steps) {
      engine.scan(nowMs: ms, inputs: {1: input});
      if (engine.output(1) != expected) {
        throw StateError('$name t=$ms I1=$input: expected Q1=$expected, got ${engine.output(1)}');
      }
    }
    print('PASS: $name');
  }

  runCase('TOF: delayed OFF and cancellation', 0, 3000, [
    (0, false, false), (100, true, true),
    (1000, false, true), (3999, false, true),
    (4000, false, false), (5000, true, true),
    (6000, false, true), (7000, true, true),
    (9000, false, true), (11999, false, true),
    (12000, false, false),
  ]);

  runCase('TON/TOF: independent ON and OFF delays', 2000, 3000, [
    (0, false, false), (100, true, false),
    (2099, true, false), (2100, true, true),
    (2500, false, true), (3000, true, true),
    (3500, false, true), (6499, false, true),
    (6500, false, false), (7000, true, false),
    (8000, false, false), (9000, true, false),
    (10999, true, false), (11000, true, true),
  ]);
  print('ALL TOF AND TON/TOF TESTS PASSED');
}
