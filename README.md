# LG Kumanda

LG webOS televizyonlar için ücretsiz ve açık kaynak iPhone kumandası. Kaynak kodu [MIT lisansı](LICENSE) ile kullanılabilir, değiştirilebilir ve paylaşılabilir.

Türkçe, açık renkli, SwiftUI ile yazılmış yerel iPhone uygulaması. iOS 17 ve üzeri; harici Swift paketi gerektirmez.

## Mac, Windows ve Android

**[22. sürümü indir](https://github.com/ertugrulerzin/LGKumanda/releases/tag/v1.0.0-preview.22):** [Android ARM64 · küçük paket](https://github.com/ertugrulerzin/LGKumanda/releases/download/v1.0.0-preview.22/LGKumanda-Android-arm64.apk) · [Android evrensel paket](https://github.com/ertugrulerzin/LGKumanda/releases/download/v1.0.0-preview.22/LGKumanda-Android-universal.apk) · [Mac DMG](https://github.com/ertugrulerzin/LGKumanda/releases/download/v1.0.0-preview.22/LGKumanda-macOS.dmg) · [Windows kurulum EXE](https://github.com/ertugrulerzin/LGKumanda/releases/download/v1.0.0-preview.22/LGKumanda-Windows-Setup.exe).

Android paketleri aynı özelliklere sahiptir: küçük paket ARM64 telefonlar içindir; evrensel paket ayrıca ARM32 ve x86_64 içerir. Mac paketi Intel ve Apple Silicon destekler. Bunlar önizleme paketleridir; imzalama ve gerçek cihaz doğrulama sınırları sürüm notlarında açıklanır.

22. sürümde birden fazla Android TV / Tivibu kutusu, kutuya özel kumanda ve sayı tuşları, HDMI girişine göre yönlendirme, TV güç durumunun takibi, IP değişikliklerinde yeniden bulma ve deneysel web video algılama bulunur.

Bu platformlar için ortak Flutter uygulaması **[`cross_platform/`](cross_platform/README.md)** dizinindedir. Kumanda, klavye/fare, uygulama ve HDMI listeleri, kanallar, kısayollar ve TV tarayıcısı içerir. Kurulum, deneme paketleri ve doğrulama sınırları için platform kılavuzuna bak. Aşağıdaki Xcode adımları iPhone uygulamasına aittir.

Claude’un son oturumunda nerede kalındığı ve tamamlanmamış işaretçisiz tarayıcı deneyi [`oturum devri notunda`](cross_platform/SESSION_HANDOFF.tr.md) açıklanmıştır.

## Neler yapabilir?

LG Kumanda, iPhone'unu aynı ağdaki LG webOS televizyonun için bir kumandaya dönüştürür. Günlük kullanımda ses ve kanal değiştirebilir, uygulama açabilir, HDMI girişleri arasında geçiş yapabilir ve TV'ye telefondan yazı gönderebilirsin.

| Özellik | Ne işe yarar? |
| --- | --- |
| **Günlük kumanda** | Ses aç/kıs, sessize al, kanal değiştir; yön tuşları, OK, geri ve ana ekran ile TV menülerinde gezin. |
| **Medya tuşları** | Destekleyen uygulamalarda oynat, duraklat, durdur ve ileri/geri sar. |
| **Uygulamalar ve kanallar** | TV'de kurulu uygulamaları ve kanal listesini görüntüle, ara ve istediğini aç. |
| **HDMI girişleri** | TV'ye bağlı cihazların girişlerini seç. Uyumlu kutularda yön ve medya komutlarını SIMPLINK/HDMI-CEC üzerinden kullan. |
| **Ana ekran kısayolları** | Netflix, YouTube, tarayıcı veya HDMI girişlerini sabitle; adlarını ve sıralarını düzenle. Kısayollar her TV için ayrı saklanır. |
| **Telefon klavyesi** | TV'nin desteklediği metin alanlarına iPhone klavyesiyle yazı gönder; Enter ve son karakteri sil komutlarını kullan. |
| **Dokunmatik kumanda** | Telefon ekranını fare alanı olarak kullan; dokunarak tıkla ve iki parmakla kaydır. Hassasiyeti ayarla. |
| **İşaretçisiz gezinme** | TV'de fare hareketi üretmeden kaydırarak yön, dokunarak OK komutu gönder. |
| **Web'de gezinme** | Adres veya arama kelimeleri yaz; telefonda açılan sayfadaki bağlantılara dokunarak aynı adresi TV tarayıcısında aç. |
| **Birden fazla TV** | Ağdaki LG TV'leri bul veya IP adresiyle ekle; kayıtlı TV'ler arasında geçiş yap ve yeniden bağlan. |
| **Güç kontrolü** | TV'yi kapat; uyumlu TV ve ağ ayarlarıyla MAC adresi üzerinden Wake-on-LAN paketi göndererek uyandırmayı dene. |

### Web tarayıcısı nasıl çalışır?

Örneğin bir web adresini telefona yazıp TV'de açabilir, ardından telefonda gördüğün bağlantılara dokunarak TV'yi aynı sayfalara yönlendirebilirsin. Bu özellik sayfa adreslerini TV'ye gönderir; ekran yansıtma yapmaz. Telefon ve TV'deki oturumlar, çerezler ve sayfa içi işlemler birbirinden bağımsızdır.

TV'de bir video oynat düğmesine veya güvenlik doğrulamasına basmak gerektiğinde **TV'de dokunmatik** alanını açabilirsin. Bu alanda fareyi hareket ettirme, küçük adımlarla hedefleme ve tıklama kontrolleri bulunur. Video oynatma, ilgili sitenin LG TV tarayıcısıyla uyumuna bağlıdır; her sitede çalışacağı garanti edilmez.

### Gerekenler ve destek sınırları

- **iOS 17 veya üzeri bir iPhone** ve yerel ağ üzerinden kumanda bağlantısını destekleyen bir **LG webOS TV** gerekir.
- Telefon ile TV aynı yerel ağda olmalı; ilk bağlantıda TV ekranındaki eşleştirme isteği kabul edilmelidir.
- Tuşlar, metin girişi ve medya kontrolleri TV modeline, yazılımına ve açık uygulamanın desteğine göre değişebilir.
- HDMI kutularına komut iletimi SIMPLINK/HDMI-CEC desteğine bağlıdır. Tivibu gibi Android TV kutuları ise Wi-Fi üzerinden doğrudan kumanda edilebilir (iPhone). Uygulama kızılötesi kumanda göndermez.
- Uyandırma için TV'nin ilgili ağ/güç ayarları ve iPhone'daki gerekli ağ yetkileri sağlanmalıdır; ayrıntılar aşağıdadır.

TV kumanda bağlantısı yerel ağ üzerinden kurulur; eşleştirme anahtarları iPhone'un Keychain alanında saklanır. Uygulama LG Electronics'in resmi ürünü değildir.

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

IP adresiyle kumanda için Yerel Ağ izni yeterlidir. 1.0 (2) sürümünden itibaren ağ araması, aynı Wi-Fi aralığındaki adreslerde LG webOS tanımlama servisini doğrudan kontrol ederek multicast yetkisi olmadan da çalışır. Tarama gerçek ağ maskesiyle sınırlandırılır; büyük ağlarda en fazla telefonun bulunduğu /24 aralığı kontrol edilir. Kayıtlı TV adreslerine öncelik verilir. 1311 servisinden alınan tanımlamanın LG Electronics üreticisini ve webOS second-screen servisini içermesi gerekir. TestFlight 1.0 (15) ile bu servis kapalıysa kumanda portu 3001 üzerinde TLS sertifikasının LG Electronics kuruluş alanı da kontrol edilir. Bu ikinci yöntem eşleştirme veya kimlik bilgisi göndermez; yalnızca aday TV listeler. Asıl kumanda bağlantısının kayıtlı sertifika doğrulaması korunur. SSDP desteği de korunur. SSDP keşfi ve yayın adresine Wake-on-LAN gönderimi gerçek iPhone'da Apple'ın **Multicast Networking** yetkisini gerektirir. Bu yetki Apple geliştirici hesabında onaylandıktan sonra `Configuration/Multicast.entitlements` dosyasını uygulama hedefinin Code Signing Entitlements ayarına ekle; ardından provisioning profile'ı yenile. Dosya temel projeye otomatik bağlanmaz; böylece bu yetkisi olmayan geliştirme hesapları IP ile kumandayı derleyebilir.

Kaynak: [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). Uyandırma ayrıca TV'deki Mobile TV On / Wake-on-LAN ayarına ve ağ bağlantısına bağlıdır.

2026-11-16 tarihinde fiziksel iPhone 14 Pro (192.168.1.9) üzerinden aynı tarama koduyla TV **192.168.1.3** adresinde bulundu. TV'nin IP'si değişmemişti; 1311 servisi bağlantıyı reddederken 3001 TLS yöntemi TV'yi tanıdı. Tarama 253 adresi tamamladı. Bu düzeltme TestFlight **1.0 (15)** paketindedir.

### Fiziksel kumandadan kapatma ve Tivibu

TestFlight **1.0 (17)**, TV'nin güç durumu bildirimlerini dinler ve ayrıca 5 saniyede bir güç durumunu sorgular. `Active Standby`, `Suspend` veya `Power Off` bildirimi geldiğinde **TV kapalı** gösterilir, kumanda bağlantısı temizlenir ve IP kurtarma taraması başlatılmaz. Ekranı kapalı ses modu ayrı tutulur. Yanıt ve ping kontrolleri 3 saniyeyle sınırlıdır; güç API'si desteklenmiyorsa bağlantı kontrolü sürer. Ağdan hiç yanıt alınmaması tek başına TV'nin kapandığını kanıtlamaz; bu durumda bağlantı kaybı/yeniden arama durumu gösterilir.

Tivibu/Android TV kutusu **kullanılan iPhone'da** kodla eşleştirilmeli ve doğru HDMI girişiyle ilişkilendirilmelidir. Başka bilgisayardaki veya simülatördeki eşleştirme telefona aktarılmaz. Uygulamada **Kumanda → Kontrol hedefi → HDMI kutusu yardımı → Wi-Fi ile kutu kumandası** yolunu izle. TV'yi kutunun girişine al, 6 karakterlik kodu gir ve HDMI girişini seç. Wi-Fi ile kumanda HDMI-CEC gerektirmez; ses TV'ye gönderilmeye devam eder.

Kutu protokolü `RemoteStart` gelmeden hazır kabul edilmez; `SetActive` yanıtında yalnız sunucuyla ortak özellikler kullanılır. Tuşlar sıraya alınır ve iptal edilmiş bağlantının sonuçları yeni oturuma uygulanmaz. Wi-Fi eşleştirmesi aktifken yön/OK için LG işaretçi bağlantısı gerekmez. Bağlantı hataları görünür; arka plana geçişte eski kutu oturumu kapatılır. Protokol başvurusu: [androidtvremote2](https://github.com/tronikos/androidtvremote2/blob/main/src/androidtvremote2/remote.py). Gerçek TV'de güç değişimi ve kutu menüsünün hareket etmesi ayrıca denenmelidir.

### IP adresi değişirse

TestFlight **1.0 (16)**, TV'nin adresini kalıcı webOS cihaz UUID'sinden ayrı tutar. Bu sürümle TV açıkken bir kez bağlanıp birkaç saniye bekle; kalıcı kimlik otomatik kaydedilir. Önceki sürümlerin TV kayıtları ve eşleştirmeleri korunur.

Sonraki bağlantılarda kayıtlı IP'deki TV'nin UUID'si, eşleştirme anahtarı gönderilmeden önce kayıtlı sertifika üzerinden kontrol edilir. Adres yanıt vermezse veya başka bir TV'ye geçmişse aynı yerel ağ taranır. **Hem UUID hem kayıtlı sertifika** eşleşen tek TV'ye bir kez yeniden bağlanılır. Yeni IP, TV kayıtlı bağlantıyı kabul ettikten sonra kaydedilir; cihaz UUID'si, adı, Keychain anahtarı, kısayolları ve uyandırma bilgileri korunur. Kullanıcı bağlantıyı iptal ettiğinde veya başka TV seçtiğinde eski taramanın sonucu uygulanmaz. Ağ aramasında elle seçilen TV de kimliği eşleşiyorsa mevcut kayıtla açılır.

LG sertifikası tek başına cihaz kimliği değildir; birden fazla TV aynı fabrika sertifikasını kullanabilir ([lgtv2 kaynak açıklaması](https://github.com/hobbyquaker/lgtv2)). Kalıcı UUID, eşleştirme yapmayan webOS `hello` mesajıyla okunur ([aiowebostv kaynak uygulaması](https://github.com/home-assistant-libs/aiowebostv/blob/main/aiowebostv/webos_client.py)). UUID vermeyen modellerde, eksik ilk kimlik kaydında, sertifika değişikliğinde veya birden fazla aynı kimlik eşleşmesinde otomatik taşıma yapılmaz. TV açık ve erişilebilir olmalı; tarama kapsamı yukarıdaki ağ sınırlarıyla aynıdır. Kapalı TV'nin değişen IP'si yanıt almadan belirlenemez; uyandırma kayıtlı MAC üzerinden çalışır.

Doğrulama: IP'nin başka bir LG'ye atanması, ortak sertifikalı farklı UUID'ler, belirsiz eşleşme, eski kayıtların okunması, iptal sonrası eski sonucun yok sayılması ve başarısız yeniden bağlantının IP kaydını değiştirmemesi otomatik testlerle sınanır.

### TV kapalıyken uyandırma

Kapalı TV ağ taramasına yanıt vermeyebilir. Önce TV açıkken bağlanıp cihazı kaydet; daha sonra **kayıtlı TV** üzerinden uyandır. TV'de **Mobil ile TV Açma / Wi-Fi ile Aç (TV On With Mobile)** etkin olmalı. Fişi çekilmiş veya ağ bağlantısını beklemede kapatan bir TV ağdan uyandırılamaz.

Uygulama TV destekliyorsa açık bağlantı sırasında ağ bilgilerini okur ve bağlı IP'ye ait Wi-Fi/Ethernet MAC adresini kaydeder. İki kart arasında güvenli seçim yapılamıyorsa adresi tahmin etmez; Cihazı düzenle bölümüne etkin ağ kartının MAC adresini elle gir. Elle girilmiş MAC ve özel yayın adresi korunur. TV'den alınabiliyorsa gerçek ağ maskesiyle yayın adresi hesaplanır.

Uyandırma kayıtlı IP'ye ve yayın adresine UDP 9/7 portlarından üç tur gönderilir. iPhone ayrıca bağlı Wi-Fi ağının gerçek yayın adresini kullanır. Paket gönderilmesi TV'nin açıldığını doğrulamaz; birkaç saniye sonra yeniden bağlan. iPhone'da doğrudan IP'ye gönderim multicast yetkisi gerektirmez, ancak beklemedeki TV'nin ağ kartı bu paketi alamayabilir; yayın gönderiminin Apple yetkisi gereksinimi devam eder. TestFlight 1.0 (13) ve 1.0 (14) dağıtım profillerinde bu yetki bulunmuyor. Ayrıntılar: [Apple yerel ağ belgesi](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [LG TV On With Mobile ayarı](https://www.lg.com/us/support/help-library/lg-tv-how-to-set-up-the-lg-thinq-app-on-your-lg-smart-tv--20152745625356).

2026-11-16 geliştirme doğrulaması: otomatik MAC seçimi ve gerçek ağ maskesi testleri geçti. Mac'ten kayıtlı gerçek TV'ye yayın paketleri gönderildi, ancak TV'nin 3001 bağlantı portu 15 saniye içinde açılmadı. Gerçek TV'de uyandırma başarısı henüz doğrulanmadı. Uyandırma değişiklikleri TestFlight 1.0 (14) paketine dahildir; preview.3 indirmelerine dahil değildir.

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
