import 'services/lynra_plc_ffi.dart' as bridge;
import 'dart:ffi';
import 'package:ffi/ffi.dart' as ffi;

import 'models/control_block.dart';
import 'services/lynra_plc_converter.dart';

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
final plc = bridge.LynraPlcFfi();
plc.printStructSizes();
print('Kalıcı FFI LynraRule: ${sizeOf<LynraRule>()} bytes');
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


  final engine = plc.createEngine();

  if (engine == nullptr) {
    throw StateError('PLC engine creation failed');
  }

  print('PLC engine created: $engine');
	
	
final success = plc.scan(engine, 100, 0);

print('PLC scan result: $success');

final outputs = plc.getOutputs(engine);
print('PLC outputs: $outputs');


final flutterRule = ControlConditionGroup(
  id: 'test-rule-1',
  conditions: [
    InputCondition(
      inputIndex: 1,
      trigger: ConditionTrigger.highLevel,
    ),
  ],
  actions: [
    ControlAction.output(
      outputIndex: 1,
      outputState: true,
    ),
  ],
);


final flutterRule2 = ControlConditionGroup(
  id: 'test-rule-2',
  conditions: [
    InputCondition(
      inputIndex: 2,
      trigger: ConditionTrigger.highLevel,
    ),
  ],
  actions: [
    ControlAction.output(
      outputIndex: 2,
      outputState: true,
    ),
  ],
);


final convertedRule = ffi.calloc<bridge.LynraRule>(2);


  LynraPlcConverter.writeRule(
    flutterRule,
    convertedRule.ref,
    1,
  );
LynraPlcConverter.writeRule(
  flutterRule2,
  (convertedRule + 1).ref,
  2,
);
  print('Converted rule ID: ${convertedRule.ref.id}');
  print('Converted conditions: ${convertedRule.ref.conditionCount}');
  print('Converted actions: ${convertedRule.ref.actionCount}');
  print('Converted input: ${convertedRule.ref.conditions[0].inputIndex}');
  print('Converted output: ${convertedRule.ref.actions[0].outputIndex}');
 


try {
  final loaded = plc.loadRules(
    engine,
    convertedRule,
    2,
  );

  print('PLC rules loaded: $loaded');

  if (!loaded) {
    throw StateError('PLC rule loading failed');
  }

  plc.scan(engine, 200, 1);
  print('I1 ON -> outputs: ${plc.getOutputs(engine)}');

  plc.scan(engine, 300, 0);
  print('I1 OFF -> outputs: ${plc.getOutputs(engine)}');
	
	plc.scan(engine, 400, 2);
print('I2 ON -> outputs: ${plc.getOutputs(engine)}');

plc.scan(engine, 500, 0);
print('I2 OFF -> outputs: ${plc.getOutputs(engine)}');

plc.scan(engine, 600, 3);
print('I1 + I2 ON -> outputs: ${plc.getOutputs(engine)}');
} finally {
  ffi.calloc.free(convertedRule);
}



  plc.destroyEngine(engine);

  print('PLC engine destroyed successfully');
}
