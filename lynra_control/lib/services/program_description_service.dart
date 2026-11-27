import '../models/control_block.dart';

class ProgramDescriptionService {
  static String seconds(int ms) => '${(ms / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '').replaceAll('.', ',')} sn';
  static String input(int i) => i == 0 ? 'YOK' : 'I$i';
  static String flag(bool v) => v ? 'Açık' : 'Kapalı';
  static String condition(InputCondition c) => switch(c.trigger) {
    ConditionTrigger.highLevel => 'I${c.inputIndex} ON',
    ConditionTrigger.lowLevel => 'I${c.inputIndex} OFF',
    ConditionTrigger.risingEdge => 'I${c.inputIndex} OFF → ON geçişi',
    ConditionTrigger.fallingEdge => 'I${c.inputIndex} ON → OFF geçişi',
  };
  static String combine(List<String> items, List<LogicOperator> ops, LogicOperator fallback) {
    if (items.isEmpty) return 'Koşul yok';
    var result = items.first;
    for (var i=1;i<items.length;i++) {
      final b=items[i];
      final op=i-1<ops.length?ops[i-1]:fallback;
      result=switch(op) {
        LogicOperator.and => '($result VE $b)',
        LogicOperator.or => '($result VEYA $b)',
        LogicOperator.xor => '($result FARKLIYSA $b)',
        LogicOperator.nand => 'DEĞİL ($result VE $b)',
        LogicOperator.nor => 'DEĞİL ($result VEYA $b)',
        LogicOperator.not => '($result DEĞİL $b)',
      };
    }
    return result;
  }
  static String conditions(ControlConditionGroup r) => r.conditionGroups.isEmpty
    ? combine(r.conditions.map(condition).toList(),r.conditionOperators,r.logicOperator)
    : combine(r.conditionGroups.map((g)=>combine(g.conditions.map(condition).toList(),g.conditionOperators,g.logicOperator)).toList(),r.groupOperators,r.groupsOperator);
  static bool isCounter(ControlAction a)=>ControlAction.counterTypes.contains(a.type);
  static bool isOutput(ControlAction a)=>const {ControlActionType.setOutput,ControlActionType.setLatch,ControlActionType.resetLatch,ControlActionType.toggleOutput}.contains(a.type);
  static ({String text,List<(String,String)> params}) describe(ControlConditionGroup r,ControlAction a) {
    final p=<(String,String)>[];
    final q='Q${a.outputIndex}';
    final th=seconds(a.timerTHMs),tl=seconds(a.timerTLMs),t=seconds(a.timerTMs);
    final reset=input(a.resetInputIndex);
    final cs=r.conditionGroups.isEmpty?r.conditions:r.conditionGroups.expand((g)=>g.conditions).toList();
    final edge=cs.length==1&&(cs.first.trigger==ConditionTrigger.risingEdge||cs.first.trigger==ConditionTrigger.fallingEdge);
    final simple = cs.length == 1 && conditions(r) == condition(cs.first);
    final c = simple ? cs.first : null;
    final yes = c == null ? 'Koşul gerçekleştiğinde' : switch(c.trigger) {
      ConditionTrigger.highLevel => 'I${c.inputIndex} ON olduğunda',
      ConditionTrigger.lowLevel => 'I${c.inputIndex} OFF olduğunda',
      ConditionTrigger.risingEdge => 'I${c.inputIndex} OFF durumundan ON durumuna geçtiğinde',
      ConditionTrigger.fallingEdge => 'I${c.inputIndex} ON durumundan OFF durumuna geçtiğinde',
    };
    final no = c == null || edge ? 'Koşul ortadan kalktığında' : 'I${c.inputIndex} ${c.trigger == ConditionTrigger.highLevel ? 'OFF' : 'ON'} olduğunda';
    String text='';
    void add(String k,String v)=>p.add((k,v));
    void extra(String s)=>text+='\n\n$s';
    void resetLevel(){if(a.resetInputIndex!=0)add('RESET',reset);if(a.resetInputIndex!=0)extra('$reset ON iken zamanlama sıfırlanır ve bu işlem $q rölesini bıraktırır.');}
    void virtual(){if(a.virtualStart)add('Sanal giriş','Açık');if(a.virtualStart)extra('Cihaz çalışmaya başladığında fiziksel koşul beklenmeden işlem başlar. Fiziksel koşul ilk gerçekleştiğinde zamanlama yeniden başlatılır.');}
    void warning(){add('T! – Ön uyarı',seconds(a.timerWarningBeforeMs));add('T!L – Uyarı kesintisi',seconds(a.timerWarningOffMs));if(a.timerWarningBeforeMs>0&&a.timerWarningOffMs>0)extra('Süre bitiminden ${seconds(a.timerWarningBeforeMs)} önce çıkış ${seconds(a.timerWarningOffMs)} boyunca OFF olur.');}
    String delay(int ms,bool random)=>random?'0–${seconds(ms)} (rastgele)':seconds(ms);
    switch(a.type){
      case ControlActionType.onOffDelay:
        if(edge){
          add('TH – Açma gecikmesi',th);add('TA – Aktif kalma süresi',a.timerTLMs==0?'0 sn (süresiz)':tl);
          add('TEKRARLA',flag(a.timerRepeat));add('YENİDEN TETİKLE',flag(a.timerRetrigger));
          text='$yes ${a.timerTHMs==0?'beklemeden':'$th sonra'} $q rölesi çeker. ${a.timerTLMs==0?'Süreye bağlı kapanma olmaz.':'$tl sonra röle bırakır.'}';
          if(a.timerRepeat)extra('TH bekleme ve TA aktif kalma çevrimi tekrarlanır.');
          extra(a.timerRetrigger?'TH beklenirken yeni tetikleme TH süresini yeniden başlatır. ON fazında yeni tetikleme yok sayılır.': 'TH beklenirken yeni tetikleme yok sayılır. ${a.timerRepeat?'ON fazında da yok sayılır.':'Çıkış ON iken yeni tetikleme çevrimi baştan başlatır.'}');
        }else{
          final h=delay(a.timerTHMs,a.timerTHRandom),l=delay(a.timerTLMs,a.timerTLRandom);
          add('TH – Açma gecikmesi',h);add('TL – Kapanma gecikmesi',l);
          text='$yes ${a.timerTHMs==0?'hemen':'$h sonra'} $q rölesi çeker. $no ${a.timerTLMs==0?'hemen':'$l sonra'} $q rölesi bırakır. Koşul bekleme sırasında değişirse gecikme iptal edilir.';
        }
        resetLevel();virtual();if(a.virtualStart&&a.resetInputIndex!=0)extra('RESET sanal başlangıcı da iptal eder; fiziksel koşul kullanılmaya devam edebilir.');break;
      case ControlActionType.wipingRelay:
        add('T – Darbe süresi',t);text='$yes $q rölesi hemen çeker. $t sonunda veya koşul daha önce ortadan kalkarsa röle bırakır. Yeni darbe için koşul yeniden gerçekleşmelidir.';if(a.timerTMs==0)text='T sıfır olduğu için çıkış ON olmaz.';virtual();break;
      case ControlActionType.edgeWipingRelay:
        final h=delay(a.timerTHMs,a.timerTHRandom),l=delay(a.timerTLMs,a.timerTLRandom);
        add('TH – Darbe süresi',h);add('TL – Ara süresi',l);add('N – Darbe sayısı',a.timerN==0?'0 (sınırsız)':'${a.timerN}');add('TEKRARLA',flag(a.timerRepeat));add('YENİDEN TETİKLE',flag(a.timerRetrigger));add('RESET',reset);
        text='$yes önce $l beklenir, ardından $q $h boyunca çekili kalır. ${a.timerN==0?'Darbeler sınırsız devam eder.':'${a.timerN} darbe üretilir.'} Koşulun ortadan kalkması diziyi kesmez.';
        if(a.timerRepeat&&a.timerN!=0)extra('Darbe dizisi tekrarlanır.');extra(a.timerRetrigger?'Yeni tetikleme diziyi ilk TL beklemesinden başlatır.':'Dizi sürerken yeni tetiklemeler yok sayılır.');if(a.resetInputIndex!=0)extra('$reset yükselen kenarı diziyi durdurur.');virtual();break;
      case ControlActionType.asynchronousPulse:
        add('TH – ON süresi',th);add('TL – OFF süresi',tl);text='$yes $q rölesi çeker; $th sonra bırakır. $tl sonra tekrar çeker. Koşul sürdükçe bu döngü tekrarlanır. $no röle hemen bırakır.';virtual();break;
      case ControlActionType.stairwayTimer:
        add('T – Kapanma süresi',t);add('YENİDEN TETİKLE',flag(a.timerRetrigger));text='$yes $q rölesi hemen çeker. $t sonra röle bırakır.';extra(a.timerRetrigger?'Yeni tetikleme kapanma süresini yeniden başlatabilir.':'Kapanma süresi devam ederken yeni tetikleme yok sayılır.');warning();break;
      case ControlActionType.multipleFunctionTimer:
        add('T – Kapanma süresi',t);add('TL – Uzun basma eşiği',tl);text='$yes $q rölesi hemen çeker. Koşul $tl dolmadan ortadan kalkarsa $t sonra röle bırakır. Koşul en az $tl sağlanırsa çıkış sürekli ON kalır. Çıkış sürekli ON iken sonraki basıp bırakma çıkışı kapatır.';warning();break;
      case ControlActionType.stopwatchTimer:
        add('T – Hedef süre',t);text='Koşul sağlandığı sürece zaman birikir. Koşul ortadan kalkınca sayım duraklar; tekrar sağlandığında devam eder. Biriken süre $t olduğunda $q rölesi çeker ve RESET gelene kadar çekili kalır.';resetLevel();virtual();break;
      case ControlActionType.upDownCounter:
        add('CNT',input(a.counterInputIndex));add('DIR',input(a.directionInputIndex));add('RESET',reset);add('START','${a.counterStartValue}');add('ON','${a.counterOn}');add('OFF','${a.counterOff}');
        text='Sayaç ${a.counterStartValue} değerinden başlar. ${input(a.counterInputIndex)} yükselen kenarında ${a.directionInputIndex==0?'bir artar':'${input(a.directionInputIndex)} OFF ise bir artar, ON ise bir azalır'}. ${a.counterOn>=a.counterOff?'${a.counterOn} veya üstünde $q rölesi çeker, ${a.counterOff} veya altında OFF olur.':'${a.counterOn} veya altında $q rölesi çeker, ${a.counterOff} veya üstünde OFF olur.'} Arada önceki durum korunur.';if(a.counterOn==a.counterOff)extra('Eşitlikte ON önceliklidir.');if(a.resetInputIndex!=0)extra('$reset ON iken sayaç START değerinde tutulur ve çıkış OFF olur.');break;
      case ControlActionType.hoursCounter:
        final target='${a.hoursTargetMs~/3600000} saat ${(a.hoursTargetMs~/60000)%60} dk';add('EN',input(a.hoursEnableInputIndex));add('R',reset);add('Ral',input(a.hoursResetAllInputIndex));add('T – Hedef süre',target);text='${input(a.hoursEnableInputIndex)} ON iken çalışma süresi birikir. Güncel süre $target olduğunda $q rölesi çeker.';if(a.resetInputIndex!=0)extra('$reset ON iken güncel süre ve çıkış sıfırlanır; toplam süre birikmeye devam edebilir.');if(a.hoursResetAllInputIndex!=0)extra('${input(a.hoursResetAllInputIndex)} ON iken güncel ve toplam süre sıfırlanır, çıkış OFF olur.');break;
      case ControlActionType.thresholdTrigger:
        add('Fre',input(a.thresholdInputIndex));add('G_T – Ölçüm penceresi',seconds(a.thresholdGateMs));add('ON','${a.thresholdOn} darbe');add('OFF','${a.thresholdOff} darbe');text='${input(a.thresholdInputIndex)} yükselen kenarları her ${seconds(a.thresholdGateMs)} ölçüm penceresinde sayılır. ${a.thresholdOn>=a.thresholdOff?'Darbe sayısı ${a.thresholdOn} değerinden büyükse $q rölesi çeker, ${a.thresholdOff} veya altındaysa OFF olur. Arada önceki durum korunur.':'Darbe sayısı ${a.thresholdOn} veya üstünde ve ${a.thresholdOff} değerinden küçükse $q rölesi çeker, aksi halde OFF olur.'}';break;
      case ControlActionType.setOutput:text='$yes $q rölesi ${a.outputState?'çeker':'bırakır'}. $no röle ${a.outputState?'bırakır':'çeker'}.';break;
      case ControlActionType.setLatch:text='$yes $q rölesi çeker. Koşul ortadan kalktığında bu işlem çıkışı değiştirmez.';break;
      case ControlActionType.resetLatch:text='$yes $q rölesi bırakır. Koşul ortadan kalktığında bu işlem çıkışı değiştirmez.';break;
      case ControlActionType.toggleOutput:text='$yes $q rölesi durum değiştirir: çekiliyse bırakır, bırakmışsa çeker. Koşul doğru kaldığı sürece tekrar değişmez.';break;
      default:text='Eski veya desteklenmeyen işlem (${a.type.name}). Çalışma açıklaması doğrulanmadı.';break;
    }
    return (text:text,params:p);
  }
}
