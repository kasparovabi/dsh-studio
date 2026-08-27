# DshStudio — CLAUDE.md

## Tuzaklar

- **Temiz klon iOS uygulamasini ICERMEZ.** `Sources/iOS/`, `project.phone.yml`,
  `Info-iOS.plist`, `scripts/ios-run.sh`, `sim-tap.sh`, `sim-drag.sh`, `testflight.py`,
  `asc.py`, `exportOptions.plist`, ayrica `GAUNTLET*.md` ve `DESIGN*.md` gitignore'da.
  Belirti: GitHub'da telefon hedefi yok, "iOS destegi silinmis" gibi gorunur. Dogrusu:
  telefon uygulamasi bilerek sadece bu makinede duruyor. **Asla commit'leme, `git add -f`
  yapma** — `project.phone.yml` icinde ACIK METIN proxy anahtari ve tailnet adresleri var.

- **`xcodegen generate` (bayraksiz) DshStudioIOS hedefini SESSIZCE SILER.** Bayraksiz
  `project.yml` okunur, o da sadece Mac hedefini tanimlar. Belirti: `-scheme DshStudioIOS`
  "scheme not found" der, iOS kodu bozulmus sanirsin. Dogrusu: daima
  `--spec project.phone.yml` ver — `project.yml`'i `include` ettigi icin superset'tir,
  Mac hedefini de kapsar. `install-mac.sh` bu yuzden phone spec varsa onu secer.

- **`.xcodeproj` gitignore'da; `project.yml` degistiyse `xcodegen generate` SART.** Yoksa
  `xcodebuild` ESKI projeyi derler: duzelttigin hata duzelmemis gorunur, var olan koda
  "cannot find X in scope" denir.

- **Port 3080'i iki ayri process dinliyor ve bu NORMALDIR.** `dsh-tailnet-proxy` tailnet
  IP'sinde (100.83.136.24:3080), `dsh-web` ise 127.0.0.1:3080'de. Belirti: `lsof -iTCP:3080`
  iki satir doner, "port cakismasi" sanirsin. Dogrusu: farkli arayuzler, cakisma yok.
  Birini oldurursen digeri ayakta kalir ve sorun cozulmus gibi gorunur.

- **`127.0.0.1:3080` cevap veriyor diye uygulama kendi sunucusunu baslatmis DEGILDIR.**
  Uygulama once yoklar; cevap varsa mevcut sunucuya baglanir (`spawnedByApp == false`) ve
  **cikista onu kapatmaz**. launchd agent'i (`com.kasparov.dsh-web`, KeepAlive) uygulama
  kapaliyken bile ayakta tutar. Belirti: uygulamayi kapattin, sunucu calisiyor — sizinti degil.

- **launchd agent'i uyandirma, uygulamanin kendi cocugunu dogurmasindan ONCE gelmeli.**
  Ikisi de 3080'i sahiplenirse launchd exit 1 dongusune girer (`ServerManager.swift:49`).

- **`com.kasparov.dsh-web-sync` bir sunucu DEGILDIR.** 15 dakikalik periyodik is
  (`RunAtLoad false`); `launchctl list` PID yerine `-` gosterir. Portu dinlemez — "ucuncu
  sunucu var" sanma, 3080 sorunlarinin sebebi degildir.

- **Kullanici uygulamayi CANLI kullaniyor.** `pkill` yok; restart gerektiren build oncesi
  haber ver. `install-mac.sh` calisan kopya varken kurulumu reddeder — hata degil, koruma
  (canli process'in altindan bundle degistirmek onu cokertir).

- **iOS uzerinde calisirken kullanicinin 3080 sunucusuna ASLA dokunma.** Canli sunucu
  gerekiyorsa 3123'te ayri bir tane ac, isin bitince kapat. Deneme oturumlarini
  `~/.dsh/sessions` altindan sil. Simulator Mac'in agini paylasir, `127.0.0.1:3123`
  dogrudan calisir. (`GAUNTLET-IOS.md`)

- **"corrupt session log: seq gap" bozuk kurulum DEGILDIR.** dsh butunluk testini gecemeyen
  loglari servis etmeyi reddeder; kullanicinin eski oturumlarinin cogu boyle. Mac logu
  kendisi okuyup kurtarir (`SessionLogReader.swift`), telefonun boyle bir yolu yok —
  **telefonda hata seridi gormek beklenen davranistir**, duzeltilecek bug degil.

- **Gecmis kurtarma Node 22.15+ ISTER, ve PATH'ten degil SABIT listeden okunur.**
  `zstdDecompressSync` o surumde geldi; `SessionLogReader` sadece `/opt/homebrew/bin/node`,
  `/usr/local/bin/node`, `/usr/bin/node` dener. Belirti: nvm ile yeni node kurdun ama hala
  "node too old" diyor — nvm yolu listede yok. Ayrica log, commit basina bir ART ARDA
  EKLENMIS zstd frame dizisidir; `zstdDecompressSync` ilk frame'de durur, kod magic'e gore
  boler. Belirti: transkriptin sadece basi gelir, gerisi kayip sanilir.

- **Tailnet adresi (100.64.0.0/10) "yerel ag" SAYILMAZ.** macOS'ta `NSAllowsLocalNetworking`
  bu araligi kapsamaz. Mac `NSAllowsArbitraryLoads` acip kisitlamayi koda tasir
  (`AppModel.isPrivateHost`); iOS `NSAllowsArbitraryLoads: false` tutup istisnayi sadece o
  aralige verir. Belirti: istek uygulamadan hic cikmadan reddedilir, "sunucu kapali" gibi gorunur.

- **Proxy, dsh'in Host-basligi loopback korumasini ZORUNLU olarak yok eder.** Yerine
  paylasilan anahtar koyar: her istek `X-Dsh-Key` tasimali (WebSocket'te `dsh-key.<deger>`
  subprotocol), sadece `/api/` ve sadece 100.64.0.0/10 peer'lari gecer (`DSH_PROXY_PEERS`).
  Anahtari tutan `~/.dsh/settings.yaml`'in TUM yetkisini alir — varsayilan `danger-full-access`.

- **dsh on surumdur; RPC yuzeyi surumler arasi kayar.** Etikete degil test ettigin surume
  sabitle: `@deepseek-ai/dsh@0.1.0-rc.7`. Sema kayarsa hatayi yut, konsola yaz — cokme yasak.

- **`sim-tap.sh`/`sim-drag.sh` icin Simulator.app ACIK olmali** — `simctl boot` tek basina
  pencere acmaz, dokunuslar sessizce duser. Varsayilan cihaz `iPhone 17 Pro` (`DSH_SIM`).

## Calistirma

```bash
cd /Users/kasparov/Developer/DshStudio
export PATH="/opt/homebrew/bin:$PATH"          # xcodegen burada

bash scripts/install-mac.sh                    # Mac: derle + /Applications'a kur

xcodegen generate --spec project.phone.yml     # phone spec superset, Mac'i de kapsar
xcodebuild -project DshStudio.xcodeproj -scheme DshStudio -configuration Debug \
  -derivedDataPath .build-mac build

bash scripts/ios-run.sh /tmp/dsh-phone.png     # iPhone: derle + simulator + goruntu
DSH_PORT=3123 bash scripts/ios-run.sh          # ayri test sunucusuna bagla

# iOS icin ayri test sunucusu (kullanicinin 3080'ine dokunma)
zsh -lc 'set -a; . ~/.hermes/.env; set +a; unset ANTHROPIC_API_KEY; \
  exec ~/.npm-global/bin/dsh web --host 127.0.0.1 --port 3123'

xcodebuild -project DshStudio.xcodeproj -scheme DshStudio -destination 'platform=macOS' test
node --test scripts/tests/tailnet-proxy.test.js
```

## Yetkili ortam

- Repo: `github.com/kasparovabi/dsh-studio` (private), tek dal `main`. Yayinlanan urun
  **sadece Mac uygulamasi**; iOS hedefi repoda yoktur.
- Mac imzasi: `CODE_SIGN_IDENTITY: "-"` (ad-hoc), team ID gerekmez. iOS Release: Manual,
  team **M6963N578Y**, profil "DSH Studio Phone AppStore", bundle `com.kasparov.dshstudio.phone`.
  `Signing.xcconfig` git'te degil; yoksa `install-mac.sh` placeholder'i kopyalar, ad-hoc calisir.
- Bu makinenin tailnet IP'si `100.83.136.24`. Tohum listesindeki `100.86.44.13` Windows'tur
  — BASKA bir cihazdir, oraya baglanip Mac'e baglandim sanma.
- TestFlight: `scripts/testflight.py`, ic tester grubu `Ekip` (`ASC_GROUP` ile degisir),
  alici `ASC_TESTER` ile verilir.

## Gizli deger nerede

- Proxy anahtari: `~/.dsh/proxy-token` (chmod 600). Her makine kendi anahtarini uretir;
  uygulamada adres basina saklanir (UserDefaults `dsh.keys`).
- Saglayici anahtarlari: `~/.dsh/.credentials.yaml` (Settings paneli buraya yazar) ve
  `~/.hermes/.env`. Ortamdan gelen anahtar panelde gorunur ama duzenlenemez.
- Hermes token havuzu: `~/.hermes/token-havuzu.json`, `token-nobetci-durum.json`.
- App Store Connect: `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8` (`ASC_KEY_ID`, `ASC_ISSUER_ID` ortamdan).
- iOS tohum sunucu adresleri + anahtar: `project.phone.yml` (`DshSeedServers`).
- Loglar: `~/Library/Logs/dsh-tailnet-proxy.log` (her peer'i yazar), `~/.dsh/web.log`,
  `~/.dsh/web-sync.log`.