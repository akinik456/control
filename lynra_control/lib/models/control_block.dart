// Unified EGER-ISE PLC program model.
// This first revision preserves the current editor API; execution comes next.

enum LogicOperator {
  and,
  or,
  xor,
  andEdge,
  nand,
  nandEdge,
	nor,
	not,
}

enum OutputBehavior { followCondition, latch }

enum ControlActionType {
  setOutput, delay, setLatch, resetLatch, toggleOutput, blinkOutput,
  stairwayOutput, multiSwitchOutput, stopwatchOutput,
  onDelay, offDelay, onOffDelay, retentiveOnDelay, wipingRelay,
  edgeWipingRelay, asynchronousPulse, randomGenerator,
  stairwayTimer, multipleFunctionTimer, stopwatchTimer,
}

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
  int onDelayMs;
  int offDelayMs;
  int onrDelayMs;
  int blinkStartDelayMs = 0;
  int blinkCount = 0;
  int blinkOnMinMs = 0;
  int blinkOnMaxMs = 0;
  int blinkOffMinMs = 0;
  int blinkOffMaxMs = 0;
  int stairWarningBeforeMs = 0;
  int stairWarningOffMs = 0;
  bool stairRetrigger = true;
  int multiLongPressMs = 2000;

  // Siemens-style function parameters. Times are stored in milliseconds.
  // These fields are independent of the legacy ON/ONR/OFF parameters.
  int timerTMs = 0;
  int timerTHMs = 0;
  int timerTLMs = 0;
  int timerN = 1;
  int timerWarningBeforeMs = 0;
  int timerWarningOffMs = 0;
  String stopwatchTimeBase = 'seconds';

  static const Set<ControlActionType> timerTypes = {
    ControlActionType.onDelay, ControlActionType.offDelay,
    ControlActionType.onOffDelay, ControlActionType.retentiveOnDelay,
    ControlActionType.wipingRelay, ControlActionType.edgeWipingRelay,
    ControlActionType.asynchronousPulse, ControlActionType.randomGenerator,
    ControlActionType.stairwayTimer, ControlActionType.multipleFunctionTimer,
    ControlActionType.stopwatchTimer,
  };

  ControlAction.timer(ControlActionType timerType, {this.outputIndex = 1})
      : assert(timerTypes.contains(timerType)),
        type = timerType,
        outputState = true,
        durationMs = 0,
        offDurationMs = 0,
        onDelayMs = 0,
        offDelayMs = 0,
        onrDelayMs = 0;


  ControlAction.output({this.outputIndex = 1, this.outputState = true, this.onDelayMs = 0, this.offDelayMs = 0, this.onrDelayMs = 0})
      : type = ControlActionType.setOutput,
        durationMs = 1000,
        offDurationMs = 0;

  ControlAction.set({this.outputIndex = 1, this.onDelayMs = 0, this.offDelayMs = 0, this.onrDelayMs = 0})
      : type = ControlActionType.setLatch,
        outputState = true,
        durationMs = 0,
        offDurationMs = 0;

  ControlAction.reset({this.outputIndex = 1, this.onDelayMs = 0, this.offDelayMs = 0, this.onrDelayMs = 0})
      : type = ControlActionType.resetLatch,
        outputState = false,
        durationMs = 0,
        offDurationMs = 0;

  ControlAction.toggle({this.outputIndex = 1, this.onDelayMs = 0, this.offDelayMs = 0, this.onrDelayMs = 0})
      : type = ControlActionType.toggleOutput,
        outputState = false,
        durationMs = 0,
        offDurationMs = 0;

  ControlAction.blink({this.outputIndex = 1, this.durationMs = 3000, this.offDurationMs = 3000, this.onDelayMs = 0, this.offDelayMs = 0, this.onrDelayMs = 0})
      : type = ControlActionType.blinkOutput,
        outputState = true;

  ControlAction.stairway({this.outputIndex = 1, this.durationMs = 60000})
      : type = ControlActionType.stairwayOutput,
        outputState = true,
        offDurationMs = 0,
        onDelayMs = 0,
        offDelayMs = 0,
        onrDelayMs = 0;

  ControlAction.multiSwitch({this.outputIndex = 1, this.durationMs = 60000})
      : type = ControlActionType.multiSwitchOutput,
        outputState = true,
        offDurationMs = 0,
        onDelayMs = 0,
        offDelayMs = 0,
        onrDelayMs = 0;

  ControlAction.stopwatch({this.outputIndex = 1, this.durationMs = 30000})
      : type = ControlActionType.stopwatchOutput,
        outputState = true,
        offDurationMs = 0,
        onDelayMs = 0,
        offDelayMs = 0,
        onrDelayMs = 0;

  ControlAction.delay({this.durationMs = 1000, this.onDelayMs = 0, this.offDelayMs = 0, this.onrDelayMs = 0})
      : type = ControlActionType.delay,
        outputIndex = 1,
        outputState = true,
        offDurationMs = 0;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (timerTypes.contains(type)) ...{
          'timerTMs': timerTMs,
          'timerTHMs': timerTHMs,
          'timerTLMs': timerTLMs,
          'timerN': timerN,
          'timerWarningBeforeMs': timerWarningBeforeMs,
          'timerWarningOffMs': timerWarningOffMs,
          'stopwatchTimeBase': stopwatchTimeBase,
        },
        if (type != ControlActionType.delay) ...{
          'outputIndex': outputIndex,
          'outputState': outputState,
        },
        if (type == ControlActionType.delay || type == ControlActionType.blinkOutput || type == ControlActionType.stairwayOutput || type == ControlActionType.multiSwitchOutput || type == ControlActionType.stopwatchOutput) 'durationMs': durationMs,
        if (type == ControlActionType.blinkOutput) 'offDurationMs': offDurationMs,
        if (type == ControlActionType.blinkOutput) 'blinkStartDelayMs': blinkStartDelayMs,
        if (type == ControlActionType.blinkOutput) 'blinkCount': blinkCount,
        if (type == ControlActionType.blinkOutput) 'blinkOnMinMs': blinkOnMinMs,
        if (type == ControlActionType.blinkOutput) 'blinkOnMaxMs': blinkOnMaxMs,
        if (type == ControlActionType.blinkOutput) 'blinkOffMinMs': blinkOffMinMs,
        if (type == ControlActionType.blinkOutput) 'blinkOffMaxMs': blinkOffMaxMs,
        if (type == ControlActionType.stairwayOutput || type == ControlActionType.multiSwitchOutput) 'stairWarningBeforeMs': stairWarningBeforeMs,
        if (type == ControlActionType.stairwayOutput || type == ControlActionType.multiSwitchOutput) 'stairWarningOffMs': stairWarningOffMs,
        if (type == ControlActionType.stairwayOutput) 'stairRetrigger': stairRetrigger,
        if (type == ControlActionType.multiSwitchOutput) 'multiLongPressMs': multiLongPressMs,
        if (type != ControlActionType.delay) ...{
          'onDelayMs': onrDelayMs > 0 ? 0 : onDelayMs,
          'offDelayMs': offDelayMs,
          'onrDelayMs': onrDelayMs,
        },
      };

  factory ControlAction.fromJson(Map<String, dynamic> json) {
    final type = ControlActionType.values.byName(json['type'] as String);
    if (ControlAction.timerTypes.contains(type)) {
      return ControlAction.timer(type, outputIndex: json['outputIndex'] as int? ?? 1)
        ..timerTMs = json['timerTMs'] as int? ?? 0
        ..timerTHMs = json['timerTHMs'] as int? ?? 0
        ..timerTLMs = json['timerTLMs'] as int? ?? 0
        ..timerN = json['timerN'] as int? ?? 1
        ..timerWarningBeforeMs = json['timerWarningBeforeMs'] as int? ?? 0
        ..timerWarningOffMs = json['timerWarningOffMs'] as int? ?? 0
        ..stopwatchTimeBase = json['stopwatchTimeBase'] as String? ?? 'seconds';
    }

    if (type == ControlActionType.setLatch) {
      return ControlAction.set(outputIndex: json['outputIndex'] as int? ?? 1, onDelayMs: json['onDelayMs'] as int? ?? 0, offDelayMs: json['offDelayMs'] as int? ?? 0, onrDelayMs: json['onrDelayMs'] as int? ?? 0);
    }
    if (type == ControlActionType.resetLatch) {
      return ControlAction.reset(outputIndex: json['outputIndex'] as int? ?? 1, onDelayMs: json['onDelayMs'] as int? ?? 0, offDelayMs: json['offDelayMs'] as int? ?? 0, onrDelayMs: json['onrDelayMs'] as int? ?? 0);
    }
    if (type == ControlActionType.blinkOutput) {
      return ControlAction.blink(outputIndex: json['outputIndex'] as int? ?? 1, durationMs: json['durationMs'] as int? ?? 3000, offDurationMs: json['offDurationMs'] as int? ?? 3000, onDelayMs: json['onDelayMs'] as int? ?? 0, offDelayMs: json['offDelayMs'] as int? ?? 0, onrDelayMs: json['onrDelayMs'] as int? ?? 0)
        ..blinkStartDelayMs = json['blinkStartDelayMs'] as int? ?? 0
        ..blinkCount = json['blinkCount'] as int? ?? 0
        ..blinkOnMinMs = json['blinkOnMinMs'] as int? ?? 0
        ..blinkOnMaxMs = json['blinkOnMaxMs'] as int? ?? 0
        ..blinkOffMinMs = json['blinkOffMinMs'] as int? ?? 0
        ..blinkOffMaxMs = json['blinkOffMaxMs'] as int? ?? 0;
    }
    if (type == ControlActionType.stairwayOutput) {
      return ControlAction.stairway(outputIndex: json['outputIndex'] as int? ?? 1, durationMs: json['durationMs'] as int? ?? 60000)
        ..stairWarningBeforeMs = json['stairWarningBeforeMs'] as int? ?? 0
        ..stairWarningOffMs = json['stairWarningOffMs'] as int? ?? 0
        ..stairRetrigger = json['stairRetrigger'] as bool? ?? true;
    }
    if (type == ControlActionType.multiSwitchOutput) {
      return ControlAction.multiSwitch(outputIndex: json['outputIndex'] as int? ?? 1, durationMs: json['durationMs'] as int? ?? 60000)
        ..multiLongPressMs = json['multiLongPressMs'] as int? ?? 2000
        ..stairWarningBeforeMs = json['stairWarningBeforeMs'] as int? ?? 0
        ..stairWarningOffMs = json['stairWarningOffMs'] as int? ?? 0;
    }
    if (type == ControlActionType.stopwatchOutput) {
      return ControlAction.stopwatch(outputIndex: json['outputIndex'] as int? ?? 1,
          durationMs: json['durationMs'] as int? ?? 30000);
    }
    if (type == ControlActionType.toggleOutput) {
      return ControlAction.toggle(outputIndex: json['outputIndex'] as int? ?? 1, onDelayMs: json['onDelayMs'] as int? ?? 0, offDelayMs: json['offDelayMs'] as int? ?? 0, onrDelayMs: json['onrDelayMs'] as int? ?? 0);
    }
    return type == ControlActionType.delay
        ? ControlAction.delay(durationMs: json['durationMs'] as int? ?? 1000)
        : ControlAction.output(
            outputIndex: json['outputIndex'] as int? ?? 1,
            outputState: json['outputState'] as bool? ?? true,
            onDelayMs: json['onDelayMs'] as int? ?? 0,
            offDelayMs: json['offDelayMs'] as int? ?? 0,
            onrDelayMs: json['onrDelayMs'] as int? ?? 0,
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
