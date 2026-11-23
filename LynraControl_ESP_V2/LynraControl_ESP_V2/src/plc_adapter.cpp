#include "plc_adapter.h"
using A = ControlActionType;
using L = LogicOperator;
static bool convertAction(const ControlAction& a, LynraAction& d) {
 switch(a.type) {
 case A::SetOutput: d.type = a.outputState ? LYNRA_OUTPUT_ON : LYNRA_OUTPUT_OFF; break;
 case A::SetLatch: d.type = LYNRA_OUTPUT_SET; break;
 case A::ResetLatch: d.type = LYNRA_OUTPUT_RESET; break;
 case A::ToggleOutput: d.type = LYNRA_OUTPUT_TOGGLE; break;
 case A::OnOffDelay: d.type = LYNRA_TIMER_ON_OFF_DELAY; break;
 case A::WipingRelay: d.type = LYNRA_TIMER_WIPING_RELAY; break;
 case A::EdgeWipingRelay: d.type = LYNRA_TIMER_EDGE_WIPING_RELAY; break;
 case A::AsynchronousPulse: d.type = LYNRA_TIMER_ASYNC_PULSE; break;
 case A::RandomGenerator: d.type = LYNRA_TIMER_RANDOM_GENERATOR; break;
 case A::StairwayTimer: d.type = LYNRA_TIMER_STAIRWAY; break;
 case A::MultipleFunctionTimer: d.type = LYNRA_TIMER_MULTI_FUNCTION; break;
 case A::StopwatchTimer: d.type = LYNRA_TIMER_STOPWATCH; break;
 case A::UpDownCounter: d.type = LYNRA_COUNTER_UP_DOWN; break;
 case A::HoursCounter: d.type = LYNRA_COUNTER_HOURS; break;
 case A::ThresholdTrigger: d.type = LYNRA_THRESHOLD_TRIGGER; break;
 default: return false;
 }
 if(a.outputIndex < 1 || a.outputIndex > 4) return false;
 d.output_index = a.outputIndex;
 if(a.timerTMs<0 || a.timerTMs>UINT32_MAX) return false; d.t_ms=a.timerTMs;
 if(a.timerTHMs<0 || a.timerTHMs>UINT32_MAX) return false; d.th_ms=a.timerTHMs;
 if(a.timerTLMs<0 || a.timerTLMs>UINT32_MAX) return false; d.tl_ms=a.timerTLMs;
 if(a.timerWarningBeforeMs<0 || a.timerWarningBeforeMs>UINT32_MAX) return false; d.warning_before_ms=a.timerWarningBeforeMs;
 if(a.timerWarningOffMs<0 || a.timerWarningOffMs>UINT32_MAX) return false; d.warning_off_ms=a.timerWarningOffMs;
 if(a.timerN<0 || a.timerN>255) return false; d.n=a.timerN;
 bool onoff=a.type==A::OnOffDelay, edge=a.type==A::EdgeWipingRelay;
 d.th_random=(onoff||edge)&&a.timerTHRandom; d.tl_random=(onoff||edge)&&a.timerTLRandom;
 d.repeat=(onoff||edge)&&a.timerRepeat;
 d.retrigger=(onoff||edge||a.type==A::StairwayTimer)&&a.timerRetrigger;
 if(a.stopwatchTimeBase=="milliseconds") d.stopwatch_time_base=0; else if(a.stopwatchTimeBase=="seconds") d.stopwatch_time_base=1; else if(a.stopwatchTimeBase=="minutes") d.stopwatch_time_base=2; else return false;
 if(onoff||a.type==A::UpDownCounter||a.type==A::HoursCounter||a.type==A::StopwatchTimer||(edge&&a.timerRepeat)) { if(a.resetInputIndex<0||a.resetInputIndex>4) return false; d.reset_input_index=a.resetInputIndex; }
 if(a.type==A::UpDownCounter) {
 if(a.counterInputIndex<1||a.counterInputIndex>4||a.directionInputIndex<0||a.directionInputIndex>4) return false;
 if((a.directionInputIndex && a.directionInputIndex==a.counterInputIndex)||(a.resetInputIndex&&(a.resetInputIndex==a.counterInputIndex||a.resetInputIndex==a.directionInputIndex))) return false;
 if(a.counterStartValue<INT32_MIN||a.counterStartValue>INT32_MAX) return false; d.counter_start_value=a.counterStartValue;
 if(a.counterOn<INT32_MIN||a.counterOn>INT32_MAX) return false; d.counter_on=a.counterOn;
 if(a.counterOff<INT32_MIN||a.counterOff>INT32_MAX) return false; d.counter_off=a.counterOff;
 d.counter_input_index=a.counterInputIndex; d.direction_input_index=a.directionInputIndex;
 }
 if(a.type==A::HoursCounter) {
 if(a.hoursEnableInputIndex<1||a.hoursEnableInputIndex>4||a.hoursResetAllInputIndex<0||a.hoursResetAllInputIndex>4||a.hoursTargetMs<=0) return false;
 if((a.resetInputIndex&&a.resetInputIndex==a.hoursEnableInputIndex)||(a.hoursResetAllInputIndex&&(a.hoursResetAllInputIndex==a.hoursEnableInputIndex||a.hoursResetAllInputIndex==a.resetInputIndex))) return false;
 d.hours_enable_input_index=a.hoursEnableInputIndex; d.hours_reset_all_input_index=a.hoursResetAllInputIndex; d.hours_target_ms=a.hoursTargetMs;
 }
 if(a.type==A::ThresholdTrigger) {
 if(a.thresholdInputIndex<1||a.thresholdInputIndex>4||a.thresholdGateMs<1000||a.thresholdGateMs>100000||a.thresholdGateMs%1000||a.thresholdOn<0||a.thresholdOn>9999||a.thresholdOff<0||a.thresholdOff>9999) return false;
 d.threshold_input_index=a.thresholdInputIndex; d.threshold_gate_ms=a.thresholdGateMs; d.threshold_on=a.thresholdOn; d.threshold_off=a.thresholdOff;
 }
 d.virtual_start=a.virtualStart&&(onoff||edge||a.type==A::WipingRelay||a.type==A::AsynchronousPulse||a.type==A::RandomGenerator||a.type==A::StopwatchTimer);
 return true;
}
bool plcConvertProgram(const ControlProgram& program, std::vector<LynraRule>& rules, String& error) {
 rules.clear(); if(!program.validate(error)) return false;
 for(const auto& block:program.controlBlocks) for(const auto& g:block.groups) {
 error="Invalid rule: "+g.id;
 if(rules.size()>=LYNRA_PLC_MAX_RULES||g.actions.empty()||g.actions.size()>LYNRA_PLC_MAX_ACTIONS||g.outputBehavior!=OutputBehavior::FollowCondition||g.onDelayMs||g.offDelayMs) return false;
 LynraRule r={}; r.id=rules.size()+1; r.run_policy=g.runPolicy==RuleRunPolicy::Once?LYNRA_RUN_ONCE:LYNRA_RUN_REPEAT;
 switch(g.logicOperator) {
 case L::And: r.logic_operator=LYNRA_LOGIC_AND; break;
 case L::Or: r.logic_operator=LYNRA_LOGIC_OR; break;
 case L::Xor: r.logic_operator=LYNRA_LOGIC_XOR; break;
 case L::Nand: r.logic_operator=LYNRA_LOGIC_NAND; break;
 case L::Nor: r.logic_operator=LYNRA_LOGIC_NOR; break;
 case L::Not: r.logic_operator=LYNRA_LOGIC_NOT; break;
 }
 auto token=[&](LynraExprOp op, uint8_t idx=0)->bool { if(r.expression_count>=LYNRA_PLC_MAX_EXPR_TOKENS) return false; auto& t=r.expression[r.expression_count++]; t.op=op; t.condition_index=idx; return true; };
 auto oper=[&](L op)->bool { switch(op) { case L::And:return token(LYNRA_EXPR_AND); case L::Or:return token(LYNRA_EXPR_OR); case L::Xor:return token(LYNRA_EXPR_XOR); case L::Nand:return token(LYNRA_EXPR_AND)&&token(LYNRA_EXPR_NOT); case L::Nor:return token(LYNRA_EXPR_OR)&&token(LYNRA_EXPR_NOT); default:return false; } };
 auto conditions=[&](const std::vector<InputCondition>& cs,const std::vector<L>& ops,L fallback,bool expr)->bool {
 if(cs.empty()) return false;
 for(size_t i=0;i<cs.size();++i) { if(r.condition_count>=LYNRA_PLC_MAX_CONDITIONS||cs[i].inputIndex<1||cs[i].inputIndex>4) return false; uint8_t idx=r.condition_count++; auto& c=r.conditions[idx]; c.input_index=cs[i].inputIndex; c.trigger=static_cast<LynraConditionTrigger>(cs[i].trigger); if(expr&&(!token(LYNRA_EXPR_CONDITION,idx)||(i&&!oper(i-1<ops.size()?ops[i-1]:fallback)))) return false; } return true; };
 if(g.conditionGroups.empty()) { if(!conditions(g.conditions,g.conditionOperators,g.logicOperator,g.conditions.size()>1&&!g.conditionOperators.empty())) return false; }
 else for(size_t i=0;i<g.conditionGroups.size();++i) { const auto& sub=g.conditionGroups[i]; if(!conditions(sub.conditions,sub.conditionOperators,sub.logicOperator,true)||(i&&!oper(i-1<g.groupOperators.size()?g.groupOperators[i-1]:g.groupsOperator))) return false; }
 for(const auto& a:g.actions) {
 if(a.type==A::StopwatchTimer && (g.actions.size()!=1||g.conditions.size()!=1||g.conditions[0].trigger!=ConditionTrigger::HighLevel||a.resetInputIndex<1||a.resetInputIndex==g.conditions[0].inputIndex||a.timerTMs<=0)) return false;
 if((a.type==A::EdgeWipingRelay||a.type==A::StairwayTimer)&&a.timerRepeat) { if(a.resetInputIndex<1||a.resetInputIndex>4) return false; for(const auto& c:g.conditions) if(c.inputIndex==a.resetInputIndex) return false; }
 if(!convertAction(a,r.actions[r.action_count])) { error="Unsupported/invalid action: "+g.id; return false; } ++r.action_count;
 }
 rules.push_back(r);
 } error=""; return true;
}
