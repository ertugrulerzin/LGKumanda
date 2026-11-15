# LG Kumanda — Mac, Windows ve Android

LG webOS televizyonlar için Türkçe, ücretsiz ve MIT lisanslı kumanda. Bu dizindeki Flutter uygulaması üç platform için ortak kaynak kodu kullanır. Ana dizindeki SwiftUI iPhone uygulaması bağımsız olarak korunur.

## Özellikler

- Aynı yerel ağda LG TV arama veya IP adresiyle ekleme; birden fazla kayıtlı TV.
- TV ekranından onaylı eşleştirme, WSS sertifika sabitleme ve sistemin güvenli depolamasında eşleştirme anahtarı.
- Ses, sessize alma, yön/OK, ana ekran, geri, ayarlar, sayılar, renkli tuşlar ve medya kontrolleri.
- TV’den okunan uygulamalar, HDMI girişleri ve kanallar; listede arama ve yenileme.
- Uygulama ve girişleri kumandaya sabitleme; kısayol adı ve sırasını düzenleme.
- İşaretçisiz yön/OK, gerçek fare, sessiz fare, hassasiyet ve küçük adımlı hedefleme.
- TV’ye metin gönderme, Enter ve son karakteri silme. Başarısız gönderimde taslak korunur.
- Adres veya Google aramasıyla TV tarayıcısını açma. Uygulama içindeki bağlantı seçimleri aynı adresi TV’de açar.
- TV’yi kapatma; uyumlu TV/ağ ayarlarıyla Wake-on-LAN.
- Geniş pencerede sol gezinme menüsü, dar pencerede/telefonda alt sekmeler. Masaüstünde yön tuşları, Enter ve Esc desteği.

## Gerekenler

Flutter **3.50.0** / Dart **3.14**, Android derlemesi için **JDK 17**. Bağımlılık sürümleri `pubspec.lock` ile sabitlenir.

| Platform | Derleme ortamı | Çıktı |
| --- | --- | --- |
| macOS | Mac, Xcode, CocoaPods | `build/macos/Build/Products/Release/LG Kumanda.app` |
| Windows | Windows, Visual Studio C++ masaüstü araçları | `build/windows/x64/runner/Release/` klasörünün tamamı |
| Android | Android SDK, JDK 17 | `build/app/outputs/flutter-apk/app-debug.apk` |

Windows uygulama içi tarayıcısı için **Microsoft Edge WebView2 Runtime** gerekir. TV ve kumanda cihazı aynı yerel ağda bulunmalıdır. macOS yerel ağ izni veya Windows güvenlik duvarı bağlantıyı engelliyorsa izin ver. Android’de internet/ağ yetkileri manifestte tanımlıdır; eski TV ve keşif HTTP bağlantıları için yerel açık metin trafiğine izin verilir. Ana TV bağlantısı varsayılan olarak WSS kullanır.

## Çalıştırma ve derleme

Bu dizinde:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos       # Mac üzerinde
flutter run -d windows     # Windows üzerinde
flutter run -d <cihaz-id>   # Android; flutter devices ile listele
```

```sh
flutter build macos --release
flutter build windows --release
flutter build apk --debug
```

Android Studio’nun Java 25 kurulumu seçiliyorsa JDK 17’yi `flutter config --jdk-dir=<JDK-17-dizini>` ile seç. Gradle 9.5 / Android Gradle Plugin 9.3.1 kullanılır. Tarayıcı eklentisi, AGP 9 uyumluluk düzeltmesini içeren yayımlayıcının `flutter_inappwebview 6.2.0-beta.3` sürümüne sabitlenmiştir. Bu bağımlılık ön sürümdür; platform derlemeleri ve arayüz testleriyle kontrol edilir.

APK geliştirme anahtarıyla imzalanan **deneme sürümüdür**; mağaza dağıtımı değildir. macOS çıktısı Developer ID ile imzalanmış/noterlenmiş dağıtım paketi değildir. Windows çıktısında EXE ile birlikte DLL ve `data` klasörlerini de taşı. Mağaza ve son kullanıcı dağıtımı için ilgili platformun imzalama işlemleri ayrıca yapılmalıdır.

GitHub’daki **Mac Windows Android** iş akışı her platformu kendi işletim sisteminde analiz eder, test eder ve derler. Başarılı çalışmanın **Artifacts** bölümünden deneme paketleri indirilebilir. İş akışı dosyası: [`multiplatform.yml`](../.github/workflows/multiplatform.yml).

## Bağlantı ve güvenlik

TV eklerken yerel IPv4 adresini gir. İlk WSS bağlantısında TV’nin sertifikası ilk kullanımda kabul edilir; yalnızca TV ekranındaki eşleştirme onayından sonra özeti ve anahtarı güvenli depolamaya kaydedilir. Sonraki bağlantı aynı sertifikayı gerektirir. Sertifika değişmişse TV’yi doğruladıktan sonra Cihazlar bölümünden yeniden eşleştir. Güvenli bağlantı kendiliğinden WS’ye düşürülmez. Eski modeller için şifresiz WS açıkça seçilebilir.

İşaretçi soketi aynı TV adresinde olmalıdır; WSS bağlantısında şifresiz işaretçi adresleri reddedilir. Eşleştirme bilgileri macOS Keychain’de, Android ve Windows’ta `flutter_secure_storage` eklentisinin platform depolarında tutulur. Cihaz adları, IP/MAC ve kısayollar yerel ayarlardır. Anahtarlar bunlara yazılmaz. Bağlantı koparsa yeniden bağlanma kullanıcı tarafından başlatılır.

Keşif, yerel IPv4 arayüzlerinin bulunduğu /24 aralıklarını tarar; en fazla dört arayüz ve aynı anda 24 istek kullanılır. Bu sürümde SSDP/multicast keşfi yoktur; farklı VLAN veya daha geniş ağlarda IP ile ekleme kullanılabilir.

## Tarayıcı ve HDMI sınırları

Tarayıcı sayfa adreslerini eşler; ekran yansıtma yapmaz. Cihazın ve TV’nin oturumları, çerezleri, doğrulamaları ve sayfa içi düğme tıklamaları birbirinden bağımsızdır. Uygulama içi tarayıcı geçici oturum kullanır. Video cihazda durdurulur; TV’de oynatmak için **TV’de dokunmatik** paneli açılır. Bu davranışın web siteleriyle uyumu ayrıca denenmelidir. AirPlay bağımlılığı yoktur.

**Deneysel işaretçisiz web gezinmesi** varsayılan kapalıdır. Son Claude oturumundaki JavaScript yaklaşımını taşır; özellikle cross-origin iframe oynatıcılarında ve sitelerin içerik güvenlik kurallarında tamamlanmış uyumluluk doğrulaması yoktur. Normal yön/OK gezinmesiyle bu deneyi karıştırma. Oturum özeti ve sıradaki doğrulama: [`SESSION_HANDOFF.tr.md`](SESSION_HANDOFF.tr.md).

HDMI kutusunun komut alması SIMPLINK/HDMI-CEC desteğine bağlıdır. HDMI açıkken telefon klavyesi ve fare devre dışıdır. Otomatik kontrol hedefinde kanal/medya komutları ön plandaki TV kanalı veya uygulamaya göre yönlendirilir. Hiçbir fiziksel TV veya kutu için bütün komutların çalıştığı iddia edilmez.

## Doğrulama kapsamı

Birim testleri kayıt/onay akışını, güvenli saklama hatalarını, sertifika kapsamını, bağlantı yarışlarını ve zaman aşımını, HDMI kanal yönlendirmesini, keşif ayrıştırmasını, adres doğrulamayı ve Wake-on-LAN paketini kapsar. Arayüz testleri 390 ve 1280 piksel genişliklerinde ilk kullanım, cihaz doğrulaması, bağlı kumanda ve metin gönderimini sahte TV yanıtlarıyla sınar.

Bu yeni uygulamanın testleri kendi başına gerçek TV’ye komut göndermez. iPhone uygulamasının önceki canlı TV sonuçları bu üç platformun doğrulaması sayılmaz.
