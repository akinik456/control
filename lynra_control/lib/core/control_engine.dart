import '../models/control_block.dart';
import '../models/control_program.dart';

/// Deterministic scan-based PLC engine. Call scan() with monotonic time in ms.
/// Outputs and sequence state live here, never in the editable program model.
class ControlEngine {
  final ControlProgram program;
  final Map<int, bool> outputs = {};
  final Map<String, _RuleState> _states = {};
  final Map<int, bool> _previousInputs = {};
  int? _lastNowMs;
  final Set<int> _resetPriority = {};
  final Map<int, int> _outputVersions = {};
  // FLASH ownership: newest activation wins; previous active FLASH resumes.
  final Map<int, String> _blinkOwners = {};
  final Map<int, int> _blinkOwnerStartedMs = {};
  final Map<int, int> _blinkSuppressedThrough = {};
  int _blinkActivationSerial = 0;

  ControlEngine(this.program);

  bool output(int index) => outputs[index] ?? false;

  void reset() {
    outputs.clear();
    _states.clear();
    _previousInputs.clear();
    _lastNowMs = null;
    _resetPriority.clear();
    _outputVersions.clear();
    _blinkOwners.clear();
    _blinkOwnerStartedMs.clear();
    _blinkSuppressedThrough.clear();
    _blinkActivationSerial = 0;
  }

  /// Input indices are 1-based. Missing inputs are treated as OFF.
  /// Rules are processed in program order; later writes win within a scan.
  void scan({required int nowMs, required Map<int, bool> inputs}) {
    if (_lastNowMs != null && nowMs < _lastNowMs!) {
      throw ArgumentError('nowMs must be monotonic');
    }
    _lastNowMs = nowMs;

    final rules = <ControlConditionGroup>[
      for (final block in program.controlBlocks) ...block.groups,
    ];
    // Resolve RESET priority independently of rule ordering.
    // A continuous RESET is active while its effective condition is true;
    // triggered RESET is prioritized on the scan in which it executes.
    _resetPriority.clear();
    final seen = <String>{};
    for (final rule in rules) {
      if (!seen.add(rule.id)) {
        throw StateError('Duplicate rule id: ${rule.id}');
      }
      final state = _states.putIfAbsent(rule.id, _RuleState.new);
      if (rule.onDelayMs < 0 || rule.offDelayMs < 0) {
        throw StateError('Negative timer duration in rule ${rule.id}');
      }
      final edgeRule = rule.conditions.any((c) =>
          c.trigger == ConditionTrigger.risingEdge ||
          c.trigger == ConditionTrigger.fallingEdge);
      final rawMatch = _matches(rule, inputs);
      // TON and TOF are independent: a short ON pulse cannot bypass TON,
      // and TOF starts only after the effective ON state has been reached.
      if (rawMatch) {
        state.rawOffSinceMs = null;
        state.rawOnSinceMs ??= nowMs;
        if (nowMs - state.rawOnSinceMs! >= rule.onDelayMs) {
          state.timedMatch = true;
        }
      } else {
        state.rawOnSinceMs = null;
        if (state.timedMatch) {
          state.rawOffSinceMs ??= nowMs;
          if (nowMs - state.rawOffSinceMs! >= rule.offDelayMs) {
            state.timedMatch = false;
            state.rawOffSinceMs = null;
          }
        }
      }
      final matched = state.timedMatch;
      final rising = matched && !state.previousMatch;
      final falling = !matched && state.previousMatch;

      // Collect FLASH activations; resolve output ownership after all rules.
      final blinkOnly = rule.executionMode == RuleExecutionMode.continuous &&
          !edgeRule && rule.actions.isNotEmpty &&
          rule.actions.every((a) => a.type == ControlActionType.blinkOutput);
      if (blinkOnly) {
        for (final action in rule.actions) {
          if (action.durationMs <= 0 || action.offDurationMs <= 0) {
            throw StateError('BLINK durations must be positive in rule ${rule.id}');
          }
        }
        if (matched && state.blinkActivationSerial == null) {
          state.blinkActivationSerial = ++_blinkActivationSerial;
        } else if (!matched) {
          state.blinkActivationSerial = null;
        }
      } else if (edgeRule) {
        // An edge is a one-scan event; pending actions survive its disappearance.
        // Each new edge is a new opportunity, regardless of run policy.
        if (rising && !state.running) _start(state, nowMs);
        if (state.running) _advance(rule, state, nowMs);
      } else {
        // A level condition starts a new cycle only after becoming true again
        // when the policy is 'once'.
        if (!matched) {
          state.completedOnce = false;
          state.running = false;
          state.actionIndex = 0;
          state.waitUntilMs = null;
          if (rule.outputBehavior == OutputBehavior.followCondition) {
            for (final action in rule.actions) {
              if (action.type == ControlActionType.setOutput) {
                _writeOutput(action.outputIndex, !action.outputState);
              }
            }
          }
        } else {
          final latchOnly = rule.actions.isNotEmpty && rule.actions.every(
            (a) => a.type == ControlActionType.setLatch ||
                   a.type == ControlActionType.resetLatch,
          );
          final canStart = rule.runPolicy == RuleRunPolicy.once
              ? !state.completedOnce
              : (!latchOnly || rising);
          if (!state.running && canStart) _start(state, nowMs);
          if (state.running) {
            _advance(rule, state, nowMs);
            if (!state.running && rule.runPolicy == RuleRunPolicy.once) {
              state.completedOnce = true;
            }
          }
        }
      }
      if (matched && !edgeRule) {
        for (final action in rule.actions) {
          if (action.type == ControlActionType.resetLatch &&
              rule.actions.every((a) => a.type != ControlActionType.delay)) {
            _resetPriority.add(action.outputIndex);
          }
        }
      }
      state.previousMatch = matched;
    }
    for (final index in _resetPriority) {
      outputs[index] = false;
      _blinkSuppressedThrough[index] = _blinkActivationSerial;
    }

    // Resolve active FLASH rules per output, independent of rule order.
    final candidates = <int, _BlinkCandidate>{};
    for (final rule in rules) {
      final state = _states[rule.id]!;
      final serial = state.blinkActivationSerial;
      if (serial == null ||
          rule.executionMode != RuleExecutionMode.continuous ||
          rule.conditions.any((c) =>
              c.trigger == ConditionTrigger.risingEdge ||
              c.trigger == ConditionTrigger.fallingEdge) ||
          rule.actions.isEmpty ||
          !rule.actions.every((a) => a.type == ControlActionType.blinkOutput)) {
        continue;
      }
      for (final action in rule.actions) {
        final index = action.outputIndex;
        if (serial <= (_blinkSuppressedThrough[index] ?? -1)) continue;
        final current = candidates[index];
        if (current == null || serial > current.serial) {
          candidates[index] = _BlinkCandidate(rule.id, serial, action);
        }
      }
    }
    final affected = {..._blinkOwners.keys, ...candidates.keys};
    for (final index in affected) {
      final candidate = candidates[index];
      final previousOwner = _blinkOwners[index];
      if (candidate == null) {
        if (previousOwner != null) {
          _blinkOwners.remove(index);
          _blinkOwnerStartedMs.remove(index);
          _writeOutput(index, false, fromBlink: true);
        }
        continue;
      }
      if (previousOwner != candidate.ruleId) {
        _blinkOwners[index] = candidate.ruleId;
        _blinkOwnerStartedMs[index] = nowMs; // New owner starts at phase zero.
      }
      final action = candidate.action;
      final period = action.durationMs + action.offDurationMs;
      final phase = (nowMs - _blinkOwnerStartedMs[index]!) % period;
      final desired = phase < action.durationMs;
      if (output(index) != desired) {
        _writeOutput(index, desired, fromBlink: true);
      }
    }

    _previousInputs
      ..clear()
      ..addAll(inputs);
  }

  bool _matches(ControlConditionGroup rule, Map<int, bool> inputs) {
    if (rule.conditions.isEmpty) return false;
    final values = rule.conditions.map((condition) {
      final current = inputs[condition.inputIndex] ?? false;
      final previous = _previousInputs[condition.inputIndex] ?? false;
      switch (condition.trigger) {
        case ConditionTrigger.highLevel:
          return current;
        case ConditionTrigger.lowLevel:
          return !current;
        case ConditionTrigger.risingEdge:
          return !previous && current;
        case ConditionTrigger.fallingEdge:
          return previous && !current;
      }
    }).toList();
    switch (rule.logicOperator) {
      case LogicOperator.and:
        return values.every((value) => value);
      case LogicOperator.or:
        return values.any((value) => value);
      case LogicOperator.xor:
        return values.where((value) => value).length.isOdd;
    }
  }

  void _start(_RuleState state, int nowMs) {
    state.running = true;
    state.actionIndex = 0;
    state.waitUntilMs = null;
    state.outputVersions = {
      for (final entry in _outputVersions.entries) entry.key: entry.value,
    };
  }

  void _writeOutput(int index, bool value, {bool fromBlink = false}) {
    // An explicit command (e.g. EDGE RESET) cancels pending FLASH ownership
    // until a new FLASH condition activation occurs.
    if (!fromBlink) {
      _blinkSuppressedThrough[index] = _blinkActivationSerial;
    }
    outputs[index] = value;
    _outputVersions[index] = (_outputVersions[index] ?? 0) + 1;
  }

  void _advance(ControlConditionGroup rule, _RuleState state, int nowMs) {
    while (state.running && state.actionIndex < rule.actions.length) {
      final action = rule.actions[state.actionIndex];
      if (action.type != ControlActionType.delay &&
          (_outputVersions[action.outputIndex] ?? 0) !=
          (state.outputVersions[action.outputIndex] ?? 0)) {
        // Another command superseded this pending output operation.
        // Skip only this output; other outputs in the sequence survive.
        state.actionIndex++;
        continue;
      }
      if (action.type == ControlActionType.blinkOutput) {
        // BLINK is driven by the level-based scan handler above.
        state.actionIndex++;
        continue;
      }
      if (action.type == ControlActionType.setOutput) {
        _writeOutput(action.outputIndex, action.outputState);
        state.outputVersions[action.outputIndex] = _outputVersions[action.outputIndex]!;
        state.actionIndex++;
        continue;
      }
      if (action.type == ControlActionType.toggleOutput) {
        _writeOutput(action.outputIndex, !output(action.outputIndex));
        state.outputVersions[action.outputIndex] = _outputVersions[action.outputIndex]!;
        state.actionIndex++;
        continue;
      }
      if (action.type == ControlActionType.setLatch) {
        _writeOutput(action.outputIndex, true);
        state.outputVersions[action.outputIndex] = _outputVersions[action.outputIndex]!;
        state.actionIndex++;
        continue;
      }
      if (action.type == ControlActionType.resetLatch) {
        _writeOutput(action.outputIndex, false);
        state.outputVersions[action.outputIndex] = _outputVersions[action.outputIndex]!;
        _resetPriority.add(action.outputIndex);
        state.actionIndex++;
        continue;
      }
      if (action.durationMs < 0) {
        throw StateError('Negative delay in rule ${rule.id}');
      }
      state.waitUntilMs ??= nowMs + action.durationMs;
      if (nowMs < state.waitUntilMs!) return;
      state.waitUntilMs = null;
      state.actionIndex++;
    }
    if (state.actionIndex >= rule.actions.length) {
      state.running = false;
    }
  }
}

class _RuleState {
  bool previousMatch = false;
  bool completedOnce = false;
  int? rawOnSinceMs;
  int? rawOffSinceMs;
  bool timedMatch = false;
  bool running = false;
  int actionIndex = 0;
  int? waitUntilMs;
  Map<int, int> outputVersions = {};
  int? blinkStartedMs;
  int? blinkActivationSerial;
}

class _BlinkCandidate {
  final String ruleId;
  final int serial;
  final ControlAction action;
  _BlinkCandidate(this.ruleId, this.serial, this.action);
}
