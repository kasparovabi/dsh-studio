# iPhone gauntlet protokolü

Her iterasyon şu sırayla işler. Derle (xcodegen + xcodebuild, iOS Simulator
hedefi), simülatöre kur ve aç, ekran görüntüsü al, DESIGN-IOS.md hedefiyle
karşılaştır, en çok sapan tek konuyu düzelt, bu dosyadaki listeyi güncelle.
Derleme iki kez üst üste kırılırsa dur ve kullanıcıya bildir.

## Doğrulama protokolü

- Simülatör: iPhone 17 Pro, iOS 26.5.
- Derleme: `xcodegen generate` sonra
  `xcodebuild -scheme DshStudioIOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build`
- Kurulum ve açılış: `xcrun simctl boot`, `install`, `launch`.
- Görüntü: `xcrun simctl io booted screenshot`.
- Kullanıcının çalışan Mac uygulamasına ve 3080 portundaki sunucusuna ASLA
  dokunma. Canlı sunucu gerektiğinde 3123'te ayrı bir tane aç:
  `zsh -lc 'set -a; . ~/.hermes/.env; set +a; unset ANTHROPIC_API_KEY; exec ~/.npm-global/bin/dsh web --host 127.0.0.1 --port 3123'`
  ve iş bitince kapat. Deneme oturumlarını `~/.dsh/sessions` altından sil.
- Simülatör Mac'in ağını paylaşır, yani 127.0.0.1:3123 doğrudan çalışır.
- Uygulamayı o sunucuya bağlamak için `DSH_PORT=3123 bash scripts/ios-run.sh`.
- Dokunma ve ekran görüntüsü: `bash scripts/sim-tap.sh <x> <y> <dosya>`, koordinat
  cihaz puntosu. Simulator.app açık olmalı, `simctl boot` tek başına pencere açmaz.
- Tur boyunca 3123 sunucusu ayakta kalıyor. 13. madde bitince kapat ve deneme
  oturumlarını sil.

## Durum listesi

- [x] 1. iOS hedefi projeye eklendi, model katmanı platformdan ayrıldı
      (NSImage yerine paylaşılan görsel tipi), simülatörde derleniyor ve açılıyor
- [x] 2. Sunucuya bağlanma, oturum listesi sayfası, oturum seçme, geçmiş yükleme
- [x] 3. Transkript iskeleti: tarih ayracı, kullanıcı balonu, asistan metni,
      boş durum, ölçüler DESIGN-IOS.md'deki gibi
- [x] 4. Kompozer birebir: siyah kap, dalga düğmesi, alan, artı, altında çip şeridi
- [x] 5. Üst bar birebir: iki yuvarlak düğme, orta kapsül, model adı ve dalga
- [x] 6. Canlı akış: assistant/chunk, üç noktalı üretiliyor satırı, dalga animasyonu
- [x] 7. Araç çağrısı satırları: rozet, başlık, durum, katlanır çıktı
- [x] 8. Onay istemleri ve seçenekli sorular, siyah aksiyon kapsülleriyle
- [x] 9. Görsel ek: fotoğraf seçici, kompozer ataşı, mesaj içi görsel, medya kartı
- [ ] 10. Kuyruk ve steer çipleri, iptal düğmesi, hata şeridi
- [ ] 11. Görsel parite turu: referansla yan yana kıyas, yarıçap, boşluk, renk düzeltmesi
- [ ] 12. Bağlam basıncı ve jeton göstergesi
- [ ] 13. Final regresyon, simülatör görüntüleri, teslim özeti

## Notlar

- Kullanıcının eski oturumlarının çoğunda günlük bozuk, `session.history` ve
  `session.models` "corrupt session log: seq gap" hatası veriyor. Mac diskten
  kurtarıyor, telefonun böyle bir yolu yok, o yüzden 10. maddedeki hata şeridi
  bu durumu göstermeli.
- Deneme için kullanıcının gerçek oturumlarını seçme. Taze deneme oturumu
  session-32196b82-8b4d-4fc7-99be-65efbdbc423f, dizini /tmp/dsh-phone-lab.
  Liste en yeniyi başa aldığı için uygulama açılışta onu seçiyor.

- Model katmanı Mac ile ortak. Sources/Model altında AppKit'e değen tek yer
  görsel tipleri ve dosya seçici, onlar platform ayrımıyla bölünecek.
- Mac tarafındaki davranış kararları burada da geçerli. Tur çalışırken
  varsayılan gönderim steer, kuyruk ayrı düğme.
- Transkript takibi Mac'teki kuralı izler. Kullanıcı yukarı kaydırınca takip
  durur, en aşağı dönünce devam eder.
