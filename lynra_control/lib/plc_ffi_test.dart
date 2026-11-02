import 'dart:ffi';
import 'package:ffi/ffi.dart' as ffi;

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

  @Bool()
  external bool outputState;

  @Uint32()
  external int durationMs;

  @Uint32()
  external int offDurationMs;

  @Uint32()
  external int onDelayMs;

  @Uint32()
  external int offDelayMs;
}

final class LynraRule extends Struct {
  @Uint32()
  external int id;

  @Int32()
  external int logicOperator;

  @Int32()
  external int outputBehavior;

  @Int32()
  external int runPolicy;

  @Uint32()
  external int onDelayMs;

  @Uint32()
  external int offDelayMs;

  @Uint8()
  external int conditionCount;

  @Array(8)
  external Array<LynraCondition> conditions;

  @Uint8()
  external int actionCount;

  @Array(16)
  external Array<LynraAction> actions;
}

typedef PlcCreateNative = Pointer<Void> Function();
typedef PlcDestroyNative = Void Function(Pointer<Void>);


typedef PlcScanNative = Uint8 Function(
  Pointer<Void>,
  Uint64,
  Uint32,
);

typedef PlcGetOutputsNative = Uint32 Function(Pointer<Void>);


typedef PlcLoadRulesNative = Bool Function(
  Pointer<Void>,
  Pointer<LynraRule>,
  IntPtr,
);



void main() {
print('LynraCondition: ${sizeOf<LynraCondition>()} bytes');
print('LynraAction: ${sizeOf<LynraAction>()} bytes');
print('LynraRule: ${sizeOf<LynraRule>()} bytes');
  final dll = DynamicLibrary.open(
    r'C:\control\lynra_control\native\cmake-build-debug\liblynra_PLC_engine.dll',
  );

  final create = dll.lookupFunction<
      PlcCreateNative,
      PlcCreateNative>('lynra_plc_create');

  final destroy = dll.lookupFunction<
      PlcDestroyNative,
      void Function(Pointer<Void>)>('lynra_plc_destroy');
			
			
final scan = dll.lookupFunction<
    PlcScanNative,
    int Function(Pointer<Void>, int, int)>('lynra_plc_scan');

final getOutputs = dll.lookupFunction<
    PlcGetOutputsNative,
    int Function(Pointer<Void>)>('lynra_plc_get_outputs');
		

final loadRules = dll.lookupFunction<
    PlcLoadRulesNative,
    bool Function(Pointer<Void>, Pointer<LynraRule>, int)
>('lynra_plc_load_rules');


  final engine = create();

  if (engine == nullptr) {
    throw StateError('PLC engine creation failed');
  }

  print('PLC engine created: $engine');
	
	
final success = scan(engine, 100, 0);

print('PLC scan result: $success');

final outputs = getOutputs(engine);
print('PLC outputs: $outputs');


final rules = ffi.calloc<LynraRule>(1);

try {
  final rule = rules.ref;

  rule.id = 1;
  rule.logicOperator = 0;   // AND
  rule.outputBehavior = 0;  // FOLLOW
  rule.runPolicy = 0;       // ONCE

  rule.onDelayMs = 0;
  rule.offDelayMs = 0;

  rule.conditionCount = 1;
  rule.conditions[0].inputIndex = 1;
  rule.conditions[0].trigger = 0; // HIGH

  rule.actionCount = 1;
  rule.actions[0].type = 0;        // OUTPUT
  rule.actions[0].outputIndex = 1;
  rule.actions[0].outputState = true;

  final loaded = loadRules(engine, rules, 1);
  print('PLC rules loaded: $loaded');

  if (!loaded) {
    throw StateError('PLC rule loading failed');
  }

  scan(engine, 200, 1);
  print('I1 ON -> outputs: ${getOutputs(engine)}');

  scan(engine, 300, 0);
  print('I1 OFF -> outputs: ${getOutputs(engine)}');
} finally {
  ffi.calloc.free(rules);
}


  destroy(engine);

  print('PLC engine destroyed successfully');
}
