
enum ProgramStepType {
  input,
  delay,
  output,
}

enum InputTrigger {
  risingEdge,
  fallingEdge,
  highLevel,
  lowLevel,
}

class ProgramStep {
  final String id;
  ProgramStepType type;

  int inputIndex;
  InputTrigger trigger;

  int durationMs;

  int outputIndex;
  bool outputState;

  ProgramStep({
    required this.id,
    required this.type,
    this.inputIndex = 1,
    this.trigger = InputTrigger.risingEdge,
    this.durationMs = 1000,
    this.outputIndex = 1,
    this.outputState = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'inputIndex': inputIndex,
      'trigger': trigger.name,
      'durationMs': durationMs,
      'outputIndex': outputIndex,
      'outputState': outputState,
    };
  }

  factory ProgramStep.fromJson(Map<String, dynamic> json) {
    return ProgramStep(
      id: json['id'] as String,
      type: ProgramStepType.values.byName(json['type'] as String),
      inputIndex: json['inputIndex'] as int? ?? 1,
      trigger: InputTrigger.values.byName(
        json['trigger'] as String? ?? 'risingEdge',
      ),
      durationMs: json['durationMs'] as int? ?? 1000,
      outputIndex: json['outputIndex'] as int? ?? 1,
      outputState: json['outputState'] as bool? ?? true,
    );
  }
}
