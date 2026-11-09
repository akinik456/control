#include "lynra_PLC_engine.h"
#include <string.h>

typedef struct { 
bool started; 
bool prev_match; 
bool output_on; 
uint64_t started_at; 
uint64_t elapsed_ms; 
uint32_t pulse_phase; 
uint64_t random_due_ms; 
bool random_pending; 
bool random_target; 
bool multi_permanent; 
bool multi_cancel_press; 
bool stairway_suppress_release; 
int32_t counter_value;
bool counter_prev_cnt;
uint64_t hours_elapsed_ms;       /* Güncel çalışma süresi */
uint64_t hours_total_ms;         /* Kümülatif çalışma süresi */
uint64_t hours_last_update_ms;   /* Son güncelleme zamanı */LynraExecutionState execution_state; 
uint32_t threshold_count;
uint32_t threshold_last_count;
uint64_t threshold_window_start_ms;
bool threshold_prev_input;
} TimerState;
struct LynraPlcEngine {
 bool in_use, has_last_scan;
 uint64_t last_scan;
 uint32_t outputs, previous_inputs, random_state;
 size_t count;
 LynraRule rules[LYNRA_PLC_MAX_RULES];
 bool rule_prev_active[LYNRA_PLC_MAX_RULES];
 TimerState timers[LYNRA_PLC_MAX_RULES][LYNRA_PLC_MAX_ACTIONS];
};
static LynraPlcEngine instance;
LynraPlcEngine *lynra_plc_create(void) {
 if (instance.in_use) return NULL;
 memset(&instance, 0, sizeof(instance)); instance.in_use = true; return &instance;
}
void lynra_plc_destroy(LynraPlcEngine *e) { if (e == &instance) memset(e, 0, sizeof(*e)); }
void lynra_plc_reset(LynraPlcEngine *e) {
 if (!e || !e->in_use) return;
 memset(e->timers, 0, sizeof(e->timers));
 for (size_t i = 0; i < e->count; ++i) {
    for (unsigned j = 0; j < e->rules[i].action_count; ++j) {
        const LynraAction *a = &e->rules[i].actions[j];

        if (a->type == LYNRA_COUNTER_UP_DOWN) {
            e->timers[i][j].counter_value =
                a->counter_start_value;
        }
    }
}
 memset(e->rule_prev_active, 0, sizeof(e->rule_prev_active));
 e->outputs = 0; e->previous_inputs = 0; e->random_state = 0x9E3779B9u; e->last_scan = 0; e->has_last_scan = false;
}
bool lynra_plc_load_rules(LynraPlcEngine *e, const LynraRule *rules, size_t count) {
 if (!e || !e->in_use || count > LYNRA_PLC_MAX_RULES || (count && !rules)) return false;
 for (size_t i = 0; i < count; ++i) {
  const LynraRule *r = &rules[i];
  if (r->run_policy > LYNRA_RUN_REPEAT ||
      !r->condition_count || r->condition_count > LYNRA_PLC_MAX_CONDITIONS ||
      !r->action_count || r->action_count > LYNRA_PLC_MAX_ACTIONS ||
      r->logic_operator > LYNRA_LOGIC_NOT) return false;
  for (unsigned c = 0; c < r->condition_count; ++c)
   if (r->conditions[c].input_index < 1 || r->conditions[c].input_index > LYNRA_PLC_MAX_INPUTS ||
       r->conditions[c].trigger > LYNRA_TRIGGER_FALLING) return false;
  for (unsigned a = 0; a < r->action_count; ++a)
   if ((r->actions[a].type != LYNRA_TIMER_ON_DELAY &&
        r->actions[a].type != LYNRA_TIMER_OFF_DELAY &&
        r->actions[a].type != LYNRA_TIMER_ON_OFF_DELAY &&
        r->actions[a].type != LYNRA_TIMER_RETENTIVE_ON_DELAY &&
        r->actions[a].type != LYNRA_TIMER_WIPING_RELAY &&
        r->actions[a].type != LYNRA_TIMER_EDGE_WIPING_RELAY &&
        r->actions[a].type != LYNRA_TIMER_ASYNC_PULSE &&
        r->actions[a].type != LYNRA_TIMER_RANDOM_GENERATOR &&
        r->actions[a].type != LYNRA_TIMER_STAIRWAY &&
        r->actions[a].type != LYNRA_TIMER_MULTI_FUNCTION &&
        r->actions[a].type != LYNRA_TIMER_STOPWATCH &&
				r->actions[a].type != LYNRA_COUNTER_UP_DOWN &&
				r->actions[a].type != LYNRA_COUNTER_HOURS &&
				r->actions[a].type != LYNRA_THRESHOLD_TRIGGER) ||
        r->actions[a].output_index < 1 || r->actions[a].output_index > LYNRA_PLC_MAX_OUTPUTS ||
        r->actions[a].reset_input_index > LYNRA_PLC_MAX_INPUTS ||
			  r->actions[a].direction_input_index > LYNRA_PLC_MAX_INPUTS ||
				(r->actions[a].type == LYNRA_COUNTER_UP_DOWN &&
				r->actions[a].counter_input_index == 0) ||
				(r->actions[a].type == LYNRA_THRESHOLD_TRIGGER &&
			  (r->actions[a].threshold_input_index < 1 ||
				r->actions[a].threshold_input_index > LYNRA_PLC_MAX_INPUTS ||
				r->actions[a].threshold_gate_ms < 1000 ||
				r->actions[a].threshold_gate_ms > 100000 ||
				r->actions[a].threshold_on > 9999 ||
				r->actions[a].threshold_off > 9999)) ||
			 r->actions[a].repeat > 1 ||
			 r->actions[a].retrigger > 1 ||
       (r->actions[a].type == LYNRA_TIMER_STOPWATCH &&
        r->actions[a].stopwatch_time_base > 2) ||
       (r->actions[a].type == LYNRA_TIMER_STAIRWAY &&
        (r->actions[a].t_ms == 0 ||
         r->actions[a].warning_before_ms > r->actions[a].t_ms ||
         r->actions[a].warning_off_ms > r->actions[a].warning_before_ms)) ||
       (r->actions[a].type == LYNRA_TIMER_MULTI_FUNCTION &&
        (r->actions[a].t_ms == 0 || r->actions[a].tl_ms == 0 ||
         r->actions[a].warning_before_ms > r->actions[a].t_ms ||
         r->actions[a].warning_off_ms > r->actions[a].warning_before_ms)) ||
       (r->actions[a].type == LYNRA_TIMER_EDGE_WIPING_RELAY &&
        (r->actions[a].n == 0 || r->actions[a].th_ms == 0 ||
				 r->actions[a].tl_ms == 0)) ||
       (r->actions[a].type == LYNRA_TIMER_ASYNC_PULSE &&
        (r->actions[a].th_ms == 0 || r->actions[a].tl_ms == 0))) return false;
 }
 if (count) memcpy(e->rules, rules, count * sizeof(*rules));
 e->count = count;
lynra_plc_reset(e);

return true;
}
/* Deterministic PRNG for repeatable PC tests and embedded behavior. */
static uint32_t random_delay(LynraPlcEngine *e, uint32_t upper_ms) {
 uint32_t x = e->random_state;
 x ^= x << 13; x ^= x >> 17; x ^= x << 5;
 e->random_state = x;
 return (uint32_t)((uint64_t)x % ((uint64_t)upper_ms + 1u));
}
static bool matches(const LynraRule *r, uint32_t inputs, uint32_t previous) {
 unsigned matched = 0, previous_matched = 0;
 for (unsigned i = 0; i < r->condition_count; ++i) {
  const LynraCondition *c = &r->conditions[i];
  uint32_t bit = 1u << (c->input_index - 1);
  bool now = (inputs & bit) != 0, before = (previous & bit) != 0;
  bool yes = c->trigger == LYNRA_TRIGGER_HIGH ? now :
             c->trigger == LYNRA_TRIGGER_LOW ? !now :
             c->trigger == LYNRA_TRIGGER_RISING ? now && !before : !now && before;
  matched += yes;
  /* Edge evaluation compares the same logical conditions across scans. */
  bool prior_yes = c->trigger == LYNRA_TRIGGER_HIGH ? before :
                   c->trigger == LYNRA_TRIGGER_LOW ? !before : false;
  previous_matched += prior_yes;
 }
 switch (r->logic_operator) {
  case LYNRA_LOGIC_AND: return matched == r->condition_count;
  case LYNRA_LOGIC_AND_EDGE: return matched == r->condition_count && previous_matched != r->condition_count;
  case LYNRA_LOGIC_OR: return matched != 0;
  case LYNRA_LOGIC_XOR: return (matched & 1u) != 0;
  case LYNRA_LOGIC_NAND: return matched != r->condition_count;
  case LYNRA_LOGIC_NAND_EDGE: return matched != r->condition_count && previous_matched == r->condition_count;
  case LYNRA_LOGIC_NOR: case LYNRA_LOGIC_NOT: return matched == 0;
  default: return false;
 }
}
bool lynra_plc_scan(LynraPlcEngine *e, uint64_t now_ms, uint32_t inputs) {
 if (!e || !e->in_use || (e->has_last_scan && now_ms < e->last_scan)) return false;
 uint32_t result = 0;
 for (size_t i = 0; i < e->count; ++i) {
  const LynraRule *r = &e->rules[i];
  bool active = matches(r, inputs, e->previous_inputs);
  /* A trigger is a rule-level event, shared by all actions. */
  bool trigger_event = active && !e->rule_prev_active[i];
  e->rule_prev_active[i] = active;

  bool rule_accept_trigger = trigger_event;
  for (unsigned j = 0; j < r->action_count; ++j) {
   const LynraAction *a = &r->actions[j];
   TimerState *s = &e->timers[i][j];
   bool on = false;
   /* Rule-level trigger admission, separate from timer output state.
      A new activation is accepted when idle, or while running in REPEAT.
      LEVEL conditions generate a new event only after deactivation. */
   bool accept_trigger = rule_accept_trigger;
	 bool reset_rising = false;

if (a->reset_input_index != 0) {
    uint32_t mask = 1u << (a->reset_input_index - 1);

    reset_rising =
        (inputs & mask) != 0 &&
        (e->previous_inputs & mask) == 0;
}
   if (a->type == LYNRA_TIMER_ON_DELAY) {
    if (!active) { s->started = false; }
    else {
     if (!s->started) { s->started = true; s->started_at = now_ms; }
     on = now_ms - s->started_at >= a->t_ms;
    }
    s->execution_state = !active ? LYNRA_EXEC_IDLE :
      on ? LYNRA_EXEC_COMPLETED : LYNRA_EXEC_RUNNING;
   } else if (a->type == LYNRA_TIMER_OFF_DELAY) {
    if (active) { s->started = false; on = true; }
    else if (s->prev_match) { s->started = true; s->started_at = now_ms; }
    if (!active && s->started) {
     on = now_ms - s->started_at < a->t_ms;
     if (!on) s->started = false;
    }
    s->execution_state = active ? LYNRA_EXEC_IDLE :
      s->started ? LYNRA_EXEC_RUNNING :
      (s->prev_match || s->execution_state == LYNRA_EXEC_RUNNING ||
       s->execution_state == LYNRA_EXEC_COMPLETED) ?
       LYNRA_EXEC_COMPLETED : LYNRA_EXEC_IDLE;
   }
   if (a->type == LYNRA_TIMER_ON_OFF_DELAY) {
    // Each input transition restarts its own delay; opposite transitions cancel it.
    if (active != s->prev_match || !s->started) {
     s->started = true;
     s->started_at = now_ms;
    }
    uint32_t delay = active ? a->th_ms : a->tl_ms;
    if (now_ms - s->started_at >= delay) s->output_on = active;
    on = s->output_on;
    s->execution_state = now_ms - s->started_at >= delay ?
      LYNRA_EXEC_COMPLETED : LYNRA_EXEC_RUNNING;
   }
   if (a->type == LYNRA_TIMER_RETENTIVE_ON_DELAY) {
    bool reset = a->reset_input_index != 0 &&
        (inputs & (1u << (a->reset_input_index - 1))) != 0;

    if (reset) {
        s->started = false;
        s->elapsed_ms = 0;
        s->output_on = false;
    } else if (!s->output_on) {
        if (accept_trigger &&
    ((a->retrigger && !s->output_on) ||
     (!s->started && s->elapsed_ms == 0))) {
            s->started = true;
            s->started_at = now_ms;
        }

        if (s->started) {
            uint64_t elapsed = now_ms - s->started_at;

            if (elapsed >= a->t_ms) {
                s->output_on = true;
                s->started = false;
                s->elapsed_ms = a->t_ms;
            }
        }
    }

    on = s->output_on;

    s->execution_state = reset ? LYNRA_EXEC_IDLE :
        s->output_on ? LYNRA_EXEC_COMPLETED :
        s->started ? LYNRA_EXEC_RUNNING : LYNRA_EXEC_IDLE;
}
   if (a->type == LYNRA_TIMER_WIPING_RELAY) {
    // Rising edge starts one pulse; a falling edge ends it immediately.
    // Holding the trigger HIGH cannot restart an expired pulse.
    if (!active) {
     s->started = false;
     s->output_on = false;
    } else if (!s->prev_match) {
     s->started = true;
     s->started_at = now_ms;
     s->output_on = true;
    }
    if (s->started && now_ms - s->started_at >= a->t_ms) {
     s->started = false;
     s->output_on = false;
    }
    on = s->output_on;
    if (s->started) s->execution_state = LYNRA_EXEC_RUNNING;
    else if (!active) s->execution_state = LYNRA_EXEC_IDLE;
    else if (s->execution_state == LYNRA_EXEC_RUNNING)
     s->execution_state = LYNRA_EXEC_COMPLETED;
   }
   if (a->type == LYNRA_TIMER_EDGE_WIPING_RELAY) {
    // Each rising edge restarts the complete N-pulse train.
    // The train continues after the trigger falls.
    if (reset_rising) {
    s->started = false;
    s->execution_state = LYNRA_EXEC_IDLE;
} else if (trigger_event && (!s->started || a->retrigger)) {
     s->started = true;
     s->started_at = now_ms;
     s->pulse_phase = 0;
     s->execution_state = LYNRA_EXEC_RUNNING;
    }
    if (s->started) {
     uint64_t elapsed = now_ms - s->started_at;
     uint64_t period = (uint64_t)a->th_ms + a->tl_ms;
     uint64_t total = (uint64_t)a->n * period;
     if (elapsed >= total) {
    if (a->repeat) {
        s->started_at = now_ms;
        s->pulse_phase = 0;
        s->execution_state = LYNRA_EXEC_RUNNING;
        on = false;
    } else {
        s->started = false;
        s->execution_state = LYNRA_EXEC_COMPLETED;
        on = false;
    }
} else {
      s->execution_state = LYNRA_EXEC_RUNNING;
      on = (elapsed % period) >= a->tl_ms;
     }
    }
   }
   if (a->type == LYNRA_TIMER_ASYNC_PULSE) {
    // En HIGH: start with an ON phase, then repeat TH ON / TL OFF.
    // En LOW: stop immediately; the next activation starts a fresh ON phase.
    if (!active) {
     s->started = false;
     on = false;
    } else {
     if (!s->started) {
      s->started = true;
      s->started_at = now_ms;
     }
     uint64_t elapsed = now_ms - s->started_at;
     uint64_t period = (uint64_t)a->th_ms + a->tl_ms;
     on = (elapsed % period) < a->th_ms;
    }
    s->execution_state = active ? LYNRA_EXEC_RUNNING : LYNRA_EXEC_IDLE;
   }
   if (a->type == LYNRA_TIMER_RANDOM_GENERATOR) {
    // LOGO random generator: each En transition is delayed randomly.
    // TH bounds ON delay; TL bounds OFF delay. Not a free-running oscillator.
    if (active != s->prev_match) {
     s->random_pending = true;
     s->random_target = active;
     uint32_t upper = active ? a->th_ms : a->tl_ms;
     uint64_t delay = random_delay(e, upper);
     s->random_due_ms = UINT64_MAX - now_ms < delay ? UINT64_MAX : now_ms + delay;
    }
    // Reversing En before expiry cancels the old transition.
    if (s->random_pending && now_ms >= s->random_due_ms) {
     s->output_on = s->random_target;
     s->random_pending = false;
    }
    on = s->output_on;
    s->execution_state = s->random_pending ? LYNRA_EXEC_RUNNING :
      s->execution_state == LYNRA_EXEC_RUNNING || active != s->prev_match ||
      s->execution_state == LYNRA_EXEC_COMPLETED ? LYNRA_EXEC_COMPLETED : LYNRA_EXEC_IDLE;
   }
   if (a->type == LYNRA_TIMER_STAIRWAY) {
    // LOGO stairway: rising Trg sets Q; falling Trg starts countdown T.
    // A new rising edge while timing retriggers the stairway cycle.
    if (reset_rising) {
    s->started = false;
    s->output_on = false;
    s->stairway_suppress_release = false;
    s->execution_state = LYNRA_EXEC_IDLE;
}
		
		if (!reset_rising && active && !s->prev_match) {
    if (!s->output_on || !s->started || a->retrigger) {
      s->output_on = true;
      s->started = false;
      s->stairway_suppress_release = false;
     } else {
      // ONCE: ignored press must not restart the countdown on release.
      s->stairway_suppress_release = true;
     }
    }
    if (!reset_rising && !active && s->prev_match) {
     if (s->stairway_suppress_release) {
      s->stairway_suppress_release = false;
     } else if (s->output_on) {
      s->started = true;
      s->started_at = now_ms;
     }
    }
    on = s->output_on;
    if (s->started && !reset_rising) {
     uint64_t elapsed = now_ms - s->started_at;
     if (elapsed >= a->t_ms) {
    s->started = false;
    s->output_on = false;
    on = false;
}else if (a->warning_before_ms && a->warning_off_ms) {
      uint64_t warning_start = (uint64_t)a->t_ms - a->warning_before_ms;
      if (elapsed >= warning_start &&
          elapsed < warning_start + a->warning_off_ms)
       on = false;
     }
    }
    s->execution_state = s->started ? LYNRA_EXEC_RUNNING :
      s->output_on ? LYNRA_EXEC_RUNNING :
      s->execution_state == LYNRA_EXEC_RUNNING ? LYNRA_EXEC_COMPLETED : LYNRA_EXEC_IDLE;
   }
   if (a->type == LYNRA_TIMER_MULTI_FUNCTION) {
    // Short press: timed output, T begins on release.
    // Long press (TL): permanent ON. Next press switches OFF.
    bool rising = active && !s->prev_match;
    bool falling = !active && s->prev_match;
    if (rising) {
				if (s->output_on) {
						s->multi_cancel_press = true;
				} else {
						s->output_on = true;
						s->started = false;
						s->multi_permanent = false;
						s->multi_cancel_press = false;
						s->started_at = now_ms;
				}
		}
    if (active && s->output_on && !s->multi_cancel_press &&
						now_ms - s->started_at >= a->tl_ms && !s->started)
				 s->multi_permanent = true;
				if (falling) {
				if (s->multi_cancel_press) {
						s->output_on = false;
						s->started = false;
						s->multi_permanent = false;
						s->multi_cancel_press = false;
				} else if (s->output_on && !s->multi_permanent) {
						if (now_ms - s->started_at >= a->tl_ms) {
								s->multi_permanent = true;
						} else {
								s->started = true;
								s->started_at = now_ms;
						}
				}
		}
    on = s->output_on;
    if (s->started && s->output_on) {
     uint64_t elapsed = now_ms - s->started_at;
     if (elapsed >= a->t_ms) {
      s->started = false; s->output_on = false; on = false;
     } else if (a->warning_before_ms && a->warning_off_ms) {
      uint64_t warning_start = (uint64_t)a->t_ms - a->warning_before_ms;
      if (elapsed >= warning_start && elapsed < warning_start + a->warning_off_ms)
       on = false;
     }
    }
    s->execution_state = s->started ? LYNRA_EXEC_RUNNING :
      s->output_on ? (s->multi_permanent ? LYNRA_EXEC_COMPLETED : LYNRA_EXEC_RUNNING) :
      s->execution_state == LYNRA_EXEC_RUNNING ? LYNRA_EXEC_COMPLETED : LYNRA_EXEC_IDLE;
   }
   if (a->type == LYNRA_TIMER_STOPWATCH) {
    bool reset = a->reset_input_index &&
        (inputs & (1u << (a->reset_input_index - 1))) != 0;

    if (reset) {
        s->started = false;
        s->elapsed_ms = 0;
        s->output_on = false;
    } else {
        if (active) {
            if (!s->started) {
                s->started = true;
                s->started_at = now_ms;
            }
        } else if (s->started) {
            uint64_t delta = now_ms - s->started_at;
            s->elapsed_ms =
                UINT64_MAX - s->elapsed_ms < delta
                    ? UINT64_MAX
                    : s->elapsed_ms + delta;
            s->started = false;
        }

        uint64_t total = s->elapsed_ms;

        if (s->started) {
            uint64_t delta = now_ms - s->started_at;
            total = UINT64_MAX - total < delta
                ? UINT64_MAX
                : total + delta;
        }

        if (total >= a->t_ms)
            s->output_on = true;
    }

    on = s->output_on;

    s->execution_state = s->output_on
        ? LYNRA_EXEC_COMPLETED
        : (s->started || s->elapsed_ms > 0)
            ? LYNRA_EXEC_RUNNING
            : LYNRA_EXEC_IDLE;
}
   if (a->type == LYNRA_COUNTER_UP_DOWN) {
    uint32_t cnt_mask = 1u << (a->counter_input_index - 1);
    bool cnt = (inputs & cnt_mask) != 0;

    bool reset = a->reset_input_index != 0 &&
        (inputs & (1u << (a->reset_input_index - 1))) != 0;

    if (reset) {
        s->counter_value = a->counter_start_value;
        s->output_on = false;
    } else if (cnt && !s->counter_prev_cnt) {
        bool down = a->direction_input_index != 0 &&
            (inputs & (1u << (a->direction_input_index - 1))) != 0;

        if (down) {
            if (s->counter_value > INT32_MIN)
                s->counter_value--;
        } else {
            if (s->counter_value < INT32_MAX)
                s->counter_value++;
        }
    }

    if (!reset) {
    if (a->counter_on >= a->counter_off) {
        if (s->counter_value >= a->counter_on)
            s->output_on = true;
        else if (s->counter_value < a->counter_off)
            s->output_on = false;
    } else {
        if (s->counter_value <= a->counter_on)
            s->output_on = true;
        else if (s->counter_value > a->counter_off)
            s->output_on = false;
    }
}

    s->counter_prev_cnt = cnt;
    on = s->output_on;

    s->execution_state = on
        ? LYNRA_EXEC_COMPLETED
        : LYNRA_EXEC_IDLE;
}
if (a->type == LYNRA_COUNTER_HOURS) {
    bool en = a->hours_enable_input_index != 0 &&
        (inputs & (1u << (a->hours_enable_input_index - 1))) != 0;

    bool reset = a->reset_input_index != 0 &&
        (inputs & (1u << (a->reset_input_index - 1))) != 0;

    bool reset_all = a->hours_reset_all_input_index != 0 &&
        (inputs & (1u << (a->hours_reset_all_input_index - 1))) != 0;

    uint64_t delta = e->has_last_scan
        ? now_ms - e->last_scan : 0;

    if (reset_all) {
        s->hours_elapsed_ms = 0;
        s->hours_total_ms = 0;
        s->output_on = false;
    } else {
        bool previous_en = a->hours_enable_input_index != 0 &&
    (e->previous_inputs &
     (1u << (a->hours_enable_input_index - 1))) != 0;

if (en && previous_en) {
    if (!reset) {
        s->hours_elapsed_ms =
            UINT64_MAX - s->hours_elapsed_ms < delta
                ? UINT64_MAX : s->hours_elapsed_ms + delta;
    }

    s->hours_total_ms =
        UINT64_MAX - s->hours_total_ms < delta
            ? UINT64_MAX : s->hours_total_ms + delta;
}

        if (reset) {
            s->hours_elapsed_ms = 0;
            s->output_on = false;
        } else if (s->hours_elapsed_ms >= a->hours_target_ms) {
            s->output_on = true;
        }
    }

    on = s->output_on;

    s->execution_state = on
        ? LYNRA_EXEC_COMPLETED
        : en ? LYNRA_EXEC_RUNNING : LYNRA_EXEC_IDLE;
}
	 if (a->type == LYNRA_THRESHOLD_TRIGGER) {
    uint32_t mask = 1u << (a->threshold_input_index - 1);
    bool fre = (inputs & mask) != 0;

    uint64_t gate_ms = a->threshold_gate_ms;

    if (!s->started) {
        s->started = true;
        s->threshold_window_start_ms += now_ms;
    }

    // Yalnızca yükselen kenarları say.
    if (fre && !s->threshold_prev_input) {
        if (s->threshold_count < UINT32_MAX)
            s->threshold_count++;
    }
    s->threshold_prev_input = fre;

    // Ölçüm penceresi tamamlandı.
    if (now_ms - s->threshold_window_start_ms >= gate_ms) {
			// Birden fazla ölçüm penceresi kaçırılmışsa
// ölçümü geçersiz say, Q durumunu koru.
if (now_ms - s->threshold_window_start_ms >= 2 * gate_ms) {
    s->threshold_count = 0;
    s->threshold_last_count = 0;
    s->threshold_window_start_ms = now_ms;
    s->threshold_prev_input = fre;

    on = s->output_on;
    s->execution_state = on
        ? LYNRA_EXEC_COMPLETED
        : LYNRA_EXEC_RUNNING;

    goto threshold_done;
}
        uint32_t fa = s->threshold_count;
        s->threshold_last_count = fa;
        s->threshold_count = 0;
        s->threshold_window_start_ms = now_ms;

        if (a->threshold_on >= a->threshold_off) {
            // Histerezisli kontrol
            if (fa > a->threshold_on)
                s->output_on = true;
            else if (fa <= a->threshold_off)
                s->output_on = false;
        } else {
            // Frekans aralığı kontrolü
            s->output_on =
                fa >= a->threshold_on &&
                fa < a->threshold_off;
        }
				threshold_done:;
    }

    on = s->output_on;

    s->execution_state = on
        ? LYNRA_EXEC_COMPLETED
        : LYNRA_EXEC_RUNNING;
}
	 if (on) result |= 1u << (a->output_index - 1);
   s->prev_match = active;
  }
 }
 e->outputs = result; e->previous_inputs = inputs; e->last_scan = now_ms; e->has_last_scan = true;
 return true;
}
uint32_t lynra_plc_get_outputs(const LynraPlcEngine *e) { return e && e->in_use ? e->outputs : 0; }

bool lynra_plc_get_stopwatch(const LynraPlcEngine *e, size_t rule_index,
                            size_t action_index, uint64_t *value) {
 if (!e || !e->in_use || !value || rule_index >= e->count) return false;
 const LynraRule *r = &e->rules[rule_index];
 if (action_index >= r->action_count) return false;
 const LynraAction *a = &r->actions[action_index];
 if (a->type != LYNRA_TIMER_STOPWATCH) return false;
 const TimerState *s = &e->timers[rule_index][action_index];
 uint64_t elapsed = s->elapsed_ms;
 if (s->started && e->has_last_scan) {
  uint64_t delta = e->last_scan - s->started_at;
  elapsed = UINT64_MAX - elapsed < delta ? UINT64_MAX : elapsed + delta;
 }
 uint64_t divisor = a->stopwatch_time_base == 0 ? 1u :
                    a->stopwatch_time_base == 1 ? 1000u : 60000u;
 *value = elapsed / divisor;
 return true;
}

/* Lifecycle support is added per timer type after its semantics are tested. */
bool lynra_plc_get_action_state(const LynraPlcEngine *e, size_t rule_index,
                                size_t action_index, LynraExecutionState *state) {
 if (!e || !e->in_use || !state || rule_index >= e->count) return false;
 const LynraRule *r = &e->rules[rule_index];
 if (action_index >= r->action_count) return false;
 LynraActionType type = r->actions[action_index].type;
 if (type != LYNRA_TIMER_STAIRWAY &&
     type != LYNRA_TIMER_MULTI_FUNCTION &&
     type != LYNRA_TIMER_STOPWATCH &&
     type != LYNRA_TIMER_RETENTIVE_ON_DELAY &&
     type != LYNRA_TIMER_RANDOM_GENERATOR &&
     type != LYNRA_TIMER_ON_DELAY &&
     type != LYNRA_TIMER_OFF_DELAY &&
     type != LYNRA_TIMER_ON_OFF_DELAY &&
     type != LYNRA_TIMER_EDGE_WIPING_RELAY &&
     type != LYNRA_TIMER_WIPING_RELAY &&
     type != LYNRA_TIMER_ASYNC_PULSE) return false;
 *state = e->timers[rule_index][action_index].execution_state;
 return true;
}
bool lynra_plc_get_rule_state(const LynraPlcEngine *e, size_t rule_index,
                              LynraExecutionState *state) {
 if (!e || !e->in_use || !state || rule_index >= e->count) return false;
 const LynraRule *r = &e->rules[rule_index];
 bool any_running = false, any_completed = false;
 for (unsigned j = 0; j < r->action_count; ++j) {
  LynraExecutionState current;
  if (!lynra_plc_get_action_state(e, rule_index, j, &current)) return false;
  if (current == LYNRA_EXEC_RUNNING) any_running = true;
  if (current == LYNRA_EXEC_COMPLETED) any_completed = true;
 }
 *state = any_running ? LYNRA_EXEC_RUNNING :
          any_completed ? LYNRA_EXEC_COMPLETED : LYNRA_EXEC_IDLE;
 return true;
}
bool lynra_plc_get_counter(
    const LynraPlcEngine *e,
    size_t rule_index,
    size_t action_index,
    int32_t *value)
{
    if (!e || !e->in_use || !value ||
        rule_index >= e->count)
        return false;

    const LynraRule *r = &e->rules[rule_index];

    if (action_index >= r->action_count)
        return false;

    if (r->actions[action_index].type !=
        LYNRA_COUNTER_UP_DOWN)
        return false;

    *value = e->timers[rule_index][action_index].counter_value;
    return true;
}
bool lynra_plc_get_hours(
    const LynraPlcEngine *e,
    size_t rule_index,
    size_t action_index,
    uint64_t *elapsed_ms,
    uint64_t *total_ms)
{
    if (!e || !e->in_use || !elapsed_ms || !total_ms ||
        rule_index >= e->count)
        return false;

    const LynraRule *r = &e->rules[rule_index];

    if (action_index >= r->action_count ||
        r->actions[action_index].type != LYNRA_COUNTER_HOURS)
        return false;

    const TimerState *s = &e->timers[rule_index][action_index];

    *elapsed_ms = s->hours_elapsed_ms;
    *total_ms = s->hours_total_ms;

    return true;
}
bool lynra_plc_get_threshold(
    const LynraPlcEngine *e,
    size_t rule_index,
    size_t action_index,
    uint32_t *pulse_count)
{
    if (!e || !e->in_use || !pulse_count ||
        rule_index >= e->count)
        return false;

    const LynraRule *r = &e->rules[rule_index];

    if (action_index >= r->action_count ||
        r->actions[action_index].type != LYNRA_THRESHOLD_TRIGGER)
        return false;

    *pulse_count =
        e->timers[rule_index][action_index].threshold_last_count;

    return true;
}
