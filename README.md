# LG Kumanda

LG webOS televizyonlar için ücretsiz ve açık kaynak iPhone kumandası. Kaynak kodu [MIT lisansı](LICENSE) ile kullanılabilir, değiştirilebilir ve paylaşılabilir.

Türkçe, açık renkli, SwiftUI ile yazılmış yerel iPhone uygulaması. iOS 17 ve üzeri; harici Swift paketi gerektirmez.

## Çalıştırma

`LGKumanda.xcodeproj` dosyasını Xcode'da aç, `LGKumanda` scheme'ini ve bir iPhone simülatörünü seç, Run'a bas. Gerçek iPhone için Signing & Capabilities bölümünde kendi Apple geliştirme takımını seç ve benzersiz bir Bundle Identifier kullan.

Proje tanımı `project.yml` içindedir. Yeniden üretmek için `xcodegen generate` kullan. Kaynaklarla birlikte Xcode projesi de teslim edilmiştir; normal kullanımda XcodeGen gerekmez.

## TV bağlantısı

1. Telefon ve LG webOS TV aynı yerel ağda olmalı.
2. **Cihazlar → Ağda LG TV ara** ile cihazı bul veya **Televizyon ekle** ile TV'nin ağ ayarlarındaki yerel IPv4 adresini yaz.
3. Öncelikle şifreli WSS bağlantısını kullan (3001). Eski modeller için şifresiz WS (3000) seçeneği vardır.
4. TV ekranındaki eşleştirme isteğini kabul et.
5. Eşleştirme anahtarı ve ilk bağlantıdaki TV sertifikasının SHA-256 özeti Keychain'e kaydedilir. Sertifika değişirse tekrar eşleştir. Anahtarlar kaynak koduna ve UserDefaults'a yazılmaz.

İlk WSS bağlantısı TV'nin kendi imzalı sertifikasını güven-on-first-use yöntemiyle kabul eder. Sonraki bağlantılar kayıtlı sertifikayla eşleşmek zorundadır. Yalnızca girilen yerel IPv4 adresine güvenilir. TV'deki eşleştirme onayı cihazın fiziksel olarak doğrulanmasını sağlar.

## Kumanda

- Yön tuşları, OK, ana ekran, geri, çıkış, ayarlar, menü, rehber, bilgi, kanal listesi.
- Ses, sessize alma, kanal değiştirme, sayısal ve renkli tuşlar, önceki kanal, altyazı, teletekst.
- Oynat, duraklat, durdur, ileri/geri sar.
- TV'den okunan uygulamalar, girişler ve kanallar; arama ve yenileme.
- Güç kapatma, MAC adresi ile Wake-on-LAN.
- Birden fazla kayıtlı TV, tekrar bağlanma, hata ve zaman aşımı durumları.

Bütün tuşların çalışması TV modeline, uygulamaya ve firmware izinlerine bağlıdır. Kızılötesi ve LG'nin özel sesli asistan protokolü desteklenmez. iPhone klavyesinin dikte özelliğiyle metin yazılabilir.

## Klavye ve fare

**Klavye** sekmesinde dokunmatik alan ve yazı alanı birlikte bulunur. Yazı alanı, Gönder, TV Enter ve TV'de son karakteri sil tuşları iPhone klavyesinin üstünde kalır. Gönderilen metin yalnızca başarılı TV yanıtından sonra temizlenir; hata olursa taslak korunur.

**İşaretçisiz** varsayılandır: tek parmakla kaydırma yön tuşu, dokunma OK gönderir. Bu mod fare hareketi üretmez ve ekrandaki imleci takip eden kediler için uygundur. Önceden görünür durumdaki imlecin ne zaman gizleneceğini TV belirler.

**Fare**: tek parmakla hareket, dokunmayla tıklama, iki parmakla dikey kaydırma. Klavyeyi gizleyince hassasiyet ayarı görünür. Hareketler göreli farklarla hesaplanır; parmak kaldırılıp yeniden konduğunda mutlak konuma sıçrama yapılmaz. Büyük farklar sınırlandırılır ve gönderim kuyruğu sınırlandırılmıştır.

## iPhone'da ağ arama ve uyandırma

IP adresiyle kumanda için Yerel Ağ izni yeterlidir. 1.0 (2) sürümünden itibaren ağ araması, aynı Wi-Fi aralığındaki adreslerde LG webOS tanımlama servisini doğrudan kontrol ederek multicast yetkisi olmadan da çalışır. Tarama gerçek ağ maskesiyle sınırlandırılır; büyük ağlarda en fazla telefonun bulunduğu /24 aralığı kontrol edilir. Kayıtlı TV adreslerine öncelik verilir. Yanıtın LG Electronics üreticisini ve webOS second-screen servisini içermesi gerekir. SSDP desteği de korunur. SSDP keşfi ve yayın adresine Wake-on-LAN gönderimi gerçek iPhone'da Apple'ın **Multicast Networking** yetkisini gerektirir. Bu yetki Apple geliştirici hesabında onaylandıktan sonra `Configuration/Multicast.entitlements` dosyasını uygulama hedefinin Code Signing Entitlements ayarına ekle; ardından provisioning profile'ı yenile. Dosya temel projeye otomatik bağlanmaz; böylece bu yetkisi olmayan geliştirme hesapları IP ile kumandayı derleyebilir.

Kaynak: [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). Uyandırma ayrıca TV'deki Mobile TV On / Wake-on-LAN ayarına ve ağ bağlantısına bağlıdır.

## Doğrulama

```sh
xcodebuild -project LGKumanda.xcodeproj -scheme LGKumanda \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Simülatör adını kendi kurulu cihazınla değiştir. Simülatörde Keychain testi için varsayılan ad-hoc kod imzalamayı açık bırak; `CODE_SIGNING_ALLOWED=NO` kullanma.

Canlı TV testi varsayılan olarak atlanır. Aynı simülatörde uygulamadan eşleştirme yaptıktan sonra aşağıdaki ortam değişkeniyle etkinleştir:

```sh
TEST_RUNNER_LG_LIVE_TV_TEST=1 xcodebuild -project LGKumanda.xcodeproj \
  -scheme LGKumanda -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' test
```

Canlı test yalnızca durum okur: yeniden eşleştirme istemeden TLS bağlantısı, ses durumu, uygulamalar, girişler, kanallar, işaretçi soketi ve SSDP keşfi. Kanal, ses, güç veya TV'deki içeriği değiştirmez. Diğer testler protokol, Keychain, MAC paketi, adres doğrulama, hareket filtresi, ekranlar arası gezinme ve klavye/fare modlarını kapsar.

2026-11-15 tarihinde iPhone 17 Pro simülatöründen gerçek **LG OLED55C64LA** ile TLS eşleştirme ve yeniden bağlantı doğrulandı; 23 uygulama, 4 giriş ve 644 kanal okundu. Bu, her tuşun her TV'de veya fiziksel iPhone'da test edildiği anlamına gelmez. Wake-on-LAN ve TV'ye metin gönderimi ayrıca cihaz üzerinde denenmelidir.

WebOS protokolü için başvuru: [aiowebostv](https://github.com/home-assistant-libs/aiowebostv). Uygulama bağımsızdır; LG Electronics tarafından yayımlanmış değildir.

## Dağıtım

Bu depo kaynak kodunu içerir. iPhone'a kurmak için projeyi Xcode ile kendi Apple geliştirme takımınla imzala. Hazır IPA veya herkese açık TestFlight bağlantısı bu depoda sunulmaz.

App Store Connect dağıtımı için `Configuration/ExportOptions.plist`, `scripts/asc.mjs` ve `scripts/verify-ipa.py` dosyaları proje sahibinin hesap ayarlarını kullanır; kendi dağıtımın için takım, Bundle ID ve profil bilgilerini uyarlaman gerekir. `scripts/asc.mjs`, anahtarları `ASC_ACCOUNT_DIR` ile belirtilen yerel dizinden okur; varsayılan dizin `~/.apple/<takım-kimliği>` şeklindedir. İmzalama anahtarlarını depoya ekleme.

Sonraki sürümlerde `project.yml` içindeki `CURRENT_PROJECT_VERSION` değerini artırıp `xcodegen generate` çalıştır. TestFlight notları `release/TESTFLIGHT_NOTES.tr.txt` içindedir. Yerel dağıtım raporları ve derleme çıktıları Git dışında tutulur.

## Ana ekran kısayolları ve platform kontrolü

Kumanda ekranındaki yıldız simgesiyle TV'ye kurulu uygulamaları ve HDMI girişlerini ana ekrana sabitleyebilir, adlarını/sırasını değiştirebilirsin. Uygulamalar ve Girişler listesinde de yıldız tuşu bulunur. Kısayollar her kayıtlı TV için ayrı saklanır. Netflix, YouTube, web tarayıcısı, TV+ ve adı Tivibu/TVP olan girişler mevcutsa ilk bağlantıda önerilir; kurulu olmayan uygulamalar için sahte kısayol oluşturulmaz.

Web tarayıcısı kısayolu iPhone'da web adresi alanını açar. Adresi yaz veya yapıştırıp **TV'de aç** düğmesine bas. `example.com` gibi adreslere HTTPS eklenir. Bu ekran Klavye sekmesindeki bağlantı simgesinden de açılabilir. Adresler iPhone uygulamasında kalıcı geçmiş olarak saklanmaz.

Kontrol hedefi menüsünde Otomatik, TV kanalları ve Uygulama/HDMI seçenekleri vardır. Otomatik mod TV'nin ön plandaki uygulamasını izler. HDMI ve uygulamalarda kanal/medya tuşları fiziksel kumanda tuşu olayları olarak gönderilir; TV kanal servisi çağrılmaz. Ses kontrolü TV'de kalır. Kumanda üzerindeki Ana ekran tuşu LG TV ana ekranını açar.

HDMI kutularında tuşların kutuya iletilmesi SIMPLINK/HDMI-CEC desteğine bağlıdır; LG'nin fiziksel kumandası bazen yalnızca kızılötesiyle çalışabilir. **Kontrol hedefi → HDMI kutusu yardımı** bölümünden giriş seçilip yön/OK denenebilir. Bir kutunun bütün komutlarının çalıştığı doğrulanmış değildir. TV metin klavyesi/fare yerine HDMI'da işaretçisiz gezinme sunulur. LG TV'deki yerel platform uygulamaları ayrı uygulama kısayolları olarak eklenebilir.

Gerçek TV kataloğunda Tivibu HDMI 3, TVP HDMI 4 olarak okundu. Bu adresler uygulamada sabitlenmez; her TV'nin kendi uygulama ve giriş kimlikleri kullanılır. Netflix, YouTube, tarayıcı açma ve `system.launcher/open` ile URL gönderimi gerçek TV'yle test edildi. HDMI kutusunun CEC yanıtı bu testin kapsamı dışındadır.

Durum değiştiren canlı test yalnızca `TEST_RUNNER_LG_LIVE_LAUNCH_TEST=1` ile etkinleşir. TV uygulamalarını geçici olarak açar ve önceki kaynağı geri yükler. Diğer canlı testler salt okunurdur.
