
import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../models/control_program.dart';
import 'lynra_plc_ffi.dart';
import 'lynra_plc_converter.dart';

class LynraNativeEngine {
  final LynraPlcFfi _plc = LynraPlcFfi();
  late final Pointer<Void> _engine;
  bool _disposed = false;

  LynraNativeEngine(ControlProgram program) {
    _engine = _plc.createEngine();

    if (_engine == nullptr) {
      throw StateError('PLC engine creation failed');
    }

    try {
      final rules = LynraPlcConverter.collectRules(program);
      final buffer = calloc<LynraRule>(rules.length == 0 ? 1 : rules.length);

      try {
        for (var i = 0; i < rules.length; i++) {
          LynraPlcConverter.writeRule(
            rules[i],
            (buffer + i).ref,
            i + 1,
          );
        }

        if (!_plc.loadRules(_engine, buffer, rules.length)) {
          throw StateError('PLC rule loading failed');
        }
      } finally {
        calloc.free(buffer);
      }
    } catch (_) {
      _plc.destroyEngine(_engine);
      rethrow;
    }
  }

  void scan({required int nowMs, required Map<int, bool> inputs}) {
    if (_disposed) throw StateError('PLC engine disposed');

    var inputMask = 0;

    for (final entry in inputs.entries) {
      if (entry.value && entry.key >= 1 && entry.key <= 32) {
        inputMask |= 1 << (entry.key - 1);
      }
    }

    if (!_plc.scan(_engine, nowMs, inputMask)) {
      throw StateError('PLC scan failed');
    }
  }

  bool output(int index) {
    if (_disposed) throw StateError('PLC engine disposed');
    if (index < 1 || index > 32) return false;

    return (_plc.getOutputs(_engine) & (1 << (index - 1))) != 0;
  }
int? counterValue(int ruleIndex, int actionIndex) {
  if (_disposed) {
    throw StateError('PLC engine disposed');
  }

  return _plc.getCounter(
    _engine,
    ruleIndex,
    actionIndex,
  );
}
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _plc.destroyEngine(_engine);
  }
}
