// Unified EGER-ISE PLC program model.
// This first revision preserves the current editor API; execution comes next.

enum LogicOperator { and, or, xor }

enum OutputBehavior { followCondition, latch }

enum ControlActionType { setOutput, delay, setLatch, resetLatch, toggleOutput, blinkOutput }

/// How a rule is evaluated.
enum RuleRunPolicy { once, repeat }

// Legacy execution mode retained for reading older saved programs.
enum RuleExecutionMode {
  /// Evaluate while the condition is true, on each PLC scan.
  continuous,
  /// Start an independent action sequence on a false -> true transition.
  triggered,
}

/// What happens when a running triggered rule is triggered again.
enum RetriggerBehavior { ignore, restart }

/// What happens when the condition becomes false during a running sequence.
enum ConditionLostBehavior { continueRunning, cancel }

/// Input level or transition required by a condition.
enum ConditionTrigger { highLevel, lowLevel, risingEdge, fallingEdge }

class InputCondition {
  int inputIndex;
  bool expectedState;
  ConditionTrigger trigger;

  InputCondition({
    required this.inputIndex,
    this.expectedState = true,
    ConditionTrigger? trigger,
  }) : trigger = trigger ??
            (expectedState ? ConditionTrigger.highLevel : ConditionTrigger.lowLevel);

  Map<String, dynamic> toJson() => {
        'inputIndex': inputIndex,
        'expectedState': expectedState,
        'trigger': trigger.name,
      };

  factory InputCondition.fromJson(Map<String, dynamic> json) {
    final expectedState = json['expectedState'] as bool? ?? true;
    return InputCondition(
      inputIndex: json['inputIndex'] as int,
      expectedState: expectedState,
      trigger: json['trigger'] == null
          ? null
          : ConditionTrigger.values.byName(json['trigger'] as String),
    );
  }
}

/// An ordered operation within the ISE section.
class ControlAction {
  ControlActionType type;
  int outputIndex;
  bool outputState;
  int durationMs;
  int offDurationMs;

  ControlAction.output({this.outputIndex = 1, this.outputState = true})
      : type = ControlActionType.setOutput,
        durationMs = 1000,
        offDurationMs = 0;

  ControlAction.set({this.outputIndex = 1})
      : type = ControlActionType.setLatch,
        outputState = true,
        durationMs = 0,
        offDurationMs = 0;

  ControlAction.reset({this.outputIndex = 1})
      : type = ControlActionType.resetLatch,
        outputState = false,
        durationMs = 0,
        offDurationMs = 0;

  ControlAction.toggle({this.outputIndex = 1})
      : type = ControlActionType.toggleOutput,
        outputState = false,
        durationMs = 0,
        offDurationMs = 0;

  ControlAction.blink({this.outputIndex = 1, this.durationMs = 3000, this.offDurationMs = 3000})
      : type = ControlActionType.blinkOutput,
        outputState = true;

  ControlAction.delay({this.durationMs = 1000})
      : type = ControlActionType.delay,
        outputIndex = 1,
        outputState = true,
        offDurationMs = 0;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (type != ControlActionType.delay) ...{
          'outputIndex': outputIndex,
          'outputState': outputState,
        },
        if (type == ControlActionType.delay || type == ControlActionType.blinkOutput) 'durationMs': durationMs,
        if (type == ControlActionType.blinkOutput) 'offDurationMs': offDurationMs,
      };

  factory ControlAction.fromJson(Map<String, dynamic> json) {
    final type = ControlActionType.values.byName(json['type'] as String);
    if (type == ControlActionType.setLatch) {
      return ControlAction.set(outputIndex: json['outputIndex'] as int? ?? 1);
    }
    if (type == ControlActionType.resetLatch) {
      return ControlAction.reset(outputIndex: json['outputIndex'] as int? ?? 1);
    }
    if (type == ControlActionType.blinkOutput) {
      return ControlAction.blink(outputIndex: json['outputIndex'] as int? ?? 1, durationMs: json['durationMs'] as int? ?? 3000, offDurationMs: json['offDurationMs'] as int? ?? 3000);
    }
    if (type == ControlActionType.toggleOutput) {
      return ControlAction.toggle(outputIndex: json['outputIndex'] as int? ?? 1);
    }
    return type == ControlActionType.delay
        ? ControlAction.delay(durationMs: json['durationMs'] as int? ?? 1000)
        : ControlAction.output(
            outputIndex: json['outputIndex'] as int? ?? 1,
            outputState: json['outputState'] as bool? ?? true,
          );
  }
}

/// One EGER-ISE rule. Runtime state is deliberately NOT stored here.
class ControlConditionGroup {
  final String id;
  LogicOperator logicOperator;
  final List<InputCondition> conditions;
  final List<ControlAction> actions;
  OutputBehavior outputBehavior;
  /// TON: condition must remain true for this duration before rule matches.
  int onDelayMs;
  /// TOF: keep the effective condition true this long after raw condition falls.
  int offDelayMs;

  RuleRunPolicy runPolicy;
  RuleExecutionMode executionMode;
  RetriggerBehavior retriggerBehavior;
  ConditionLostBehavior conditionLostBehavior;

  ControlConditionGroup({
    required this.id,
    this.logicOperator = LogicOperator.and,
    List<InputCondition>? conditions,
    List<ControlAction>? actions,
    this.outputBehavior = OutputBehavior.followCondition,
    this.onDelayMs = 0,
    this.offDelayMs = 0,
    this.runPolicy = RuleRunPolicy.repeat,
    this.executionMode = RuleExecutionMode.continuous,
    this.retriggerBehavior = RetriggerBehavior.ignore,
    this.conditionLostBehavior = ConditionLostBehavior.continueRunning,
  })  : conditions = conditions ?? [],
        actions = actions ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'logicOperator': logicOperator.name,
        'conditions': conditions.map((e) => e.toJson()).toList(),
        'actions': actions.map((e) => e.toJson()).toList(),
        'outputBehavior': outputBehavior.name,
        'onDelayMs': onDelayMs,
        'offDelayMs': offDelayMs,
        'runPolicy': runPolicy.name,
        'executionMode': executionMode.name,
        'retriggerBehavior': retriggerBehavior.name,
        'conditionLostBehavior': conditionLostBehavior.name,
      };

  factory ControlConditionGroup.fromJson(Map<String, dynamic> json) =>
      ControlConditionGroup(
        id: json['id'] as String,
        logicOperator: LogicOperator.values.byName(
            json['logicOperator'] as String? ?? 'and'),
        conditions: (json['conditions'] as List? ?? [])
            .map((e) => InputCondition.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        actions: (json['actions'] as List? ?? [])
            .map((e) => ControlAction.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        outputBehavior: OutputBehavior.values.byName(
            json['outputBehavior'] as String? ?? 'followCondition'),
        onDelayMs: json['onDelayMs'] as int? ?? 0,
        offDelayMs: json['offDelayMs'] as int? ?? 0,
        runPolicy: RuleRunPolicy.values.byName(
            json['runPolicy'] as String? ?? 'repeat'),
        executionMode: RuleExecutionMode.values.byName(
            json['executionMode'] as String? ?? 'continuous'),
        retriggerBehavior: RetriggerBehavior.values.byName(
            json['retriggerBehavior'] as String? ?? 'ignore'),
        conditionLostBehavior: ConditionLostBehavior.values.byName(
            json['conditionLostBehavior'] as String? ?? 'continueRunning'),
      );
}

class ControlBlock {
  final String id;
  final List<ControlConditionGroup> groups;

  // Temporary compatibility with the current Flutter editor / diagram.
  // Remove these fields when that UI is migrated to groups only.
  LogicOperator logicOperator;
  OutputBehavior outputBehavior;
  final List<InputCondition> conditions;
  int outputIndex;
  bool outputState;

  ControlBlock({
    required this.id,
    List<ControlConditionGroup>? groups,
    this.logicOperator = LogicOperator.and,
    this.outputBehavior = OutputBehavior.followCondition,
    List<InputCondition>? conditions,
    this.outputIndex = 1,
    this.outputState = true,
  })  : groups = groups ?? [],
        conditions = conditions ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'groups': groups.map((e) => e.toJson()).toList(),
      };

  factory ControlBlock.fromJson(Map<String, dynamic> json) => ControlBlock(
        id: json['id'] as String,
        groups: (json['groups'] as List? ?? [])
            .map((e) => ControlConditionGroup.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
