class FunctionHelpData {
  static const counterTitles = ['İleri / Geri Sayıcı', 'Çalışma Saati Sayacı', 'Frekans Eşik Tetikleyici'];
  static const counterDescriptions = [
    'CNT girişinin her yükselen kenarında sayaç bir artar veya azalır. DIR OFF ise ileri, ON ise geri sayar. Çıkış ON ve OFF eşiklerine göre durum değiştirir. RESET sayacı START değerine döndürür.',
    'EN girişi ON iken güncel ve toplam çalışma süreleri birikir. EN OFF iken süreler duraklar. Güncel süre hedefe ulaştığında çıkış ON olur ve resetlenene kadar ON kalır.',
    'Fre girişinin yükselen kenarları G_T ölçüm süresi boyunca sayılır. Her pencere sonunda darbe adedi ON ve OFF eşikleriyle karşılaştırılır. Çıkış ölçüm penceresi sonunda güncellenir.',
  ];
  static const extraTitles = ['Asenkron Darbe Üreteci','Merdiven Otomatiği','Çok İşlevli Anahtar','Kronometre'];
  static const extraDescriptions = [
    'Koşul doğru olduğunda çıkış hemen ON olur. TH boyunca ON, TL boyunca OFF kalır ve bu döngü tekrarlanır. Koşul yanlış olduğunda çıkış hemen OFF olur. Yeni aktivasyon ON fazından başlar.',
    'Seçilen giriş kenarı gerçekleştiğinde çıkış hemen ON olur ve T süresi başlar. T süresi sonunda çıkış OFF olur. Kapanmadan önce kısa bir OFF kesintisi ile uyarı verilebilir.',
    'Giriş ON olduğunda çıkış hemen ON olur. Kısa basıp bırakma T süresini başlatır. T süresi sonunda çıkış OFF olur. Kapanmadan önce kısa bir OFF kesintisi ile uyarı verilebilir.\n\nTL kadar veya daha uzun basma çıkışı sürekli ON tutar. Çıkış sürekli ON durumundayken sonraki basıp bırakma çıkışı OFF yapar.',
    'Giriş ON iken süre birikir, OFF iken duraklar. Biriken süre T değerine ulaştığında çıkış ON olur ve RESET gelene kadar ON kalır.',
  ];
  static const edgeWipingRelay = 'Kenar Tetiklemeli Darbe Rölesi';
  static const edgeWiping = 'Seçilen kenar gerçekleştiğinde önce TL süresi beklenir, ardından çıkış TH süresince ON olur. Bu işlem N kez gerçekleşir. Girişin sonraki seviyesi darbeyi kesmez.';
  static const edgeWipingRepeat = 'Açık ise darbe dizisi RESET gelene kadar tekrarlanır. N sıfır ise tekrar zorunludur.';
  static const edgeWipingRetrigger = 'Açık ise yeni tetikleme mevcut diziyi keser ve ilk TL beklemesinden yeniden başlatır. Kapalı ise dizi devam ederken yeni tetiklemeler yok sayılır.';
  static const edgeWipingReset = 'Seçilen RESET girişinin yükselen kenarı darbe dizisini durdurur ve çıkışı OFF yapar. Tekrarlama sırasında kullanılabilir.';
  static const edgeWipingVirtual = 'Sanal giriş seçilmiş ise, cihaza enerji verildiğinde harici tetikleme olmadan darbe dizisi başlar. İlk TL süresi sonunda çıkış ON olur. Fiziksel giriş koşulu ilk kez gerçekleştiğinde dizi yeniden başlar.';
  static const edgeWipingRandom = 'SABİT seçildiğinde ayarlanan süre kullanılır. RASTGELE seçildiğinde her ilgili süre için 0 ile ayarlanan değer arasında yeni bir süre seçilir.';

  static const wipingRelay = 'Darbe Rölesi';
  static const wipingLevel = 'EĞER koşulu doğru olduğunda çıkış hemen ON olur ve T süresi başlar. T dolduğunda veya koşul daha önce yanlış olduğunda çıkış OFF olur. Yeni bir darbe için koşul yeniden doğru olmalıdır.';
  static const wipingVirtual = 'Sanal giriş seçilmiş ise, cihaza enerji verildiğinde çıkış harici tetikleme olmadan ON olur. T süresi sonunda OFF olur. Fiziksel giriş koşulu gerçekleştiğinde kontrol fiziksel girişe geçer ve yeni bir darbe başlar.';

  static const onOffDelay = 'Açma / Kapanma Gecikmesi';
  static const level = 'EĞER koşulu doğru olduğunda TH süresi başlar. Süre dolunca çıkış ON olur. Koşul yanlış olduğunda TL süresi başlar; süre dolunca çıkış OFF olur. Koşul süre dolmadan tersine dönerse önceki bekleme iptal edilir.';
  static const edge = 'Tek girişin yükselen veya düşen kenarı ile tetiklenir. TH sonunda çıkış ON olur ve TA boyunca açık kalır. TA sıfırsa çıkış RESET veya kabul edilen yeni tetiklemeye kadar açık kalır.';
  static const reset = 'Seçilen RESET girişi ON olduğu sürece bu fonksiyonun çıkışı OFF olur ve zamanlama sıfırlanır. RESET önceliklidir.';
  static const virtual = 'Sanal giriş seçilmiş ise, cihaza enerji verildiği anda fiziksel girişlerin durumundan bağımsız olarak giriş koşulu bir kez gerçekleşmiş kabul edilir. \nBöylece herhangi bir harici tetiklemeye gerek kalmadan, cihaz açıldıktan TH süresi sonra çıkış aktif olur.';
  static const repeat = 'Açıkken TH (OFF) ve TA (ON) süreleri döngü halinde tekrarlanır. Editörde her iki süre en az 1 saniyedir.';
  static const retrigger = 'Açık: TH beklenirken yeni kenar TH süresini yeniden başlatır; çıkış ON iken yeni kenar dikkate alınmaz. \nKapalı: TH beklenirken yeni kenar yok sayılır. TEKRARLA da kapalıysa çıkış ON iken yeni kenar çıkışı OFF yapıp TH süresini yeniden başlatır.';
}
