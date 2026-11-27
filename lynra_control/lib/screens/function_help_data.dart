class FunctionHelpData {
  static const onOffDelay = 'Açma / Kapanma Gecikmesi';
  static const level = 'EĞER koşulu doğru olduğunda TH süresi başlar. Süre dolunca çıkış ON olur. Koşul yanlış olduğunda TL süresi başlar; süre dolunca çıkış OFF olur. Koşul süre dolmadan tersine dönerse önceki bekleme iptal edilir.';
  static const edge = 'Tek girişin yükselen veya düşen kenarı ile tetiklenir. TH sonunda çıkış ON olur ve TA boyunca açık kalır. TA sıfırsa çıkış RESET veya kabul edilen yeni tetiklemeye kadar açık kalır.';
  static const reset = 'Seçilen RESET girişi ON olduğu sürece bu fonksiyonun çıkışı OFF olur ve zamanlama sıfırlanır. RESET önceliklidir.';
  static const virtual = 'Sanal giriş seçilmiş ise, cihaza enerji verildiği anda fiziksel girişlerin durumundan bağımsız olarak giriş koşulu bir kez gerçekleşmiş kabul edilir. \nBöylece herhangi bir harici tetiklemeye gerek kalmadan, cihaz açıldıktan TH süresi sonra çıkış aktif olur.';
  static const repeat = 'Açıkken TH (OFF) ve TA (ON) süreleri döngü halinde tekrarlanır. Editörde her iki süre en az 1 saniyedir.';
  static const retrigger = 'Açık: TH beklenirken yeni kenar TH süresini yeniden başlatır; çıkış ON iken yeni kenar dikkate alınmaz. \nKapalı: TH beklenirken yeni kenar yok sayılır. TEKRARLA da kapalıysa çıkış ON iken yeni kenar çıkışı OFF yapıp TH süresini yeniden başlatır.';
}
