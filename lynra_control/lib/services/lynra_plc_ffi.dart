
import 'dart:ffi';
import 'package:ffi/ffi.dart';

final class LynraCondition extends Struct {
  @Uint8()
  external int inputIndex;

  @Int32()
  external int trigger;
}

final class LynraAction extends Struct {
  @Int32()
  external int type;

  @Uint8()
  external int outputIndex;

  @Uint32()
  external int tMs;

  @Uint32()
  external int thMs;

  @Uint32()
  external int tlMs;

  @Uint32()
  external int warningBeforeMs;

  @Uint32()
  external int warningOffMs;

  @Uint8()
  external int n;

  @Uint8()
  external int stopwatchTimeBase;

  @Uint8()
  external int resetInputIndex;
	
	@Uint8()
	external int repeat;
	
	@Uint8()
	external int retrigger;
	
	@Uint8()
	external int counterInputIndex;

	@Uint8()
	external int directionInputIndex;

	@Int32()
	external int counterStartValue;

	@Int32()
	external int counterOn;

	@Int32()
	external int counterOff;
}

final class LynraRule extends Struct {
  @Uint32()
  external int id;

  @Int32()
  external int logicOperator;

  @Int32()
  external int runPolicy;

  @Uint8()
  external int conditionCount;

  @Array(8)
  external Array<LynraCondition> conditions;

  @Uint8()
  external int actionCount;

  @Array(16)
  external Array<LynraAction> actions;
}

class LynraPlcFfi {
  late final DynamicLibrary _library;

  LynraPlcFfi() {
    _library = DynamicLibrary.open('liblynra_PLC_engine.so');
    
  }
	
	
Pointer<Void> createEngine() {
  final create = _library.lookupFunction<
      Pointer<Void> Function(),
      Pointer<Void> Function()
  >('lynra_plc_create');

  return create();
}

void destroyEngine(Pointer<Void> engine) {
  final destroy = _library.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
  >('lynra_plc_destroy');

  destroy(engine);
}

bool scan(
  Pointer<Void> engine,
  int nowMs,
  int inputMask,
) {
  final nativeScan = _library.lookupFunction<
      Uint8 Function(Pointer<Void>, Uint64, Uint32),
      int Function(Pointer<Void>, int, int)
  >('lynra_plc_scan');

  return nativeScan(engine, nowMs, inputMask) != 0;
}

int getOutputs(Pointer<Void> engine) {
  final nativeGetOutputs = _library.lookupFunction<
      Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
  >('lynra_plc_get_outputs');

  return nativeGetOutputs(engine);
}
int? getCounter(
  Pointer<Void> engine,
  int ruleIndex,
  int actionIndex,
) {
  final nativeGetCounter = _library.lookupFunction<
      Uint8 Function(Pointer<Void>, IntPtr, IntPtr, Pointer<Int32>),
      int Function(Pointer<Void>, int, int, Pointer<Int32>)
  >('lynra_plc_get_counter');

  final value = calloc<Int32>();

  try {
    final ok = nativeGetCounter(
      engine,
      ruleIndex,
      actionIndex,
      value,
    );

    return ok != 0 ? value.value : null;
  } finally {
    calloc.free(value);
  }
}

bool loadRules(
  Pointer<Void> engine,
  Pointer<LynraRule> rules,
  int ruleCount,
) {
  final nativeLoadRules = _library.lookupFunction<
      Uint8 Function(Pointer<Void>, Pointer<LynraRule>, IntPtr),
      int Function(Pointer<Void>, Pointer<LynraRule>, int)
  >('lynra_plc_load_rules');

  return nativeLoadRules(engine, rules, ruleCount) != 0;
}



void printStructSizes() {
  print('Condition: ${sizeOf<LynraCondition>()}');
  print('Action: ${sizeOf<LynraAction>()}');
  print('Rule: ${sizeOf<LynraRule>()}');
}


}
