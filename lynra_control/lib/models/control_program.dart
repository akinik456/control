
import 'control_block.dart';
import 'program_step.dart';

class ControlProgram {
  String name;

  final List<ProgramStep> steps;
  final List<ControlBlock> controlBlocks;

  ControlProgram({
    required this.name,
    List<ProgramStep>? steps,
    List<ControlBlock>? controlBlocks,
  })  : steps = steps ?? [],
        controlBlocks = controlBlocks ?? [];

  Map<String, dynamic> toJson() => {
        'formatVersion': 2,
        'name': name,
        'steps': steps.map((step) => step.toJson()).toList(),
        'controlBlocks':
            controlBlocks.map((block) => block.toJson()).toList(),
      };

  factory ControlProgram.fromJson(Map<String, dynamic> json) {
    final version = json['formatVersion'];

    if (version != 1 && version != 2) {
      throw FormatException(
        'Unsupported program format version: $version',
      );
    }

    return ControlProgram(
      name: json['name'] as String,

      steps: ((json['steps'] as List?) ?? [])
          .map(
            (item) => ProgramStep.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),

      controlBlocks: version == 2
          ? ((json['controlBlocks'] as List?) ?? [])
              .map(
                (item) => ControlBlock.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList()
          : [],
    );
  }
}
