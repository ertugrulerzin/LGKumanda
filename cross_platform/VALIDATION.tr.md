# 22. sürüm doğrulaması

17 Kasım 2026 — iPhone 1.0 (22) işlevlerinin ortak Flutter uygulamasına aktarımı.

- `flutter analyze`: temiz.
- `flutter test`: 38 başarılı, bir gerçek kutu testi isteğe bağlı olduğu için atlandı.
- Yeni kontroller: eski tek kutu kaydının korunması, iki kutunun adı/girişi/etkinlik durumunun ayrılması, RemoteStart öncesi tuş göndermeme, anlaşılmış özellikler ve sırayla tuş iletimi, kanal numarası ve duraklat/devam; IP değişince depolama kimliğinin ve kısayolların korunması; güç bildirimiyle beklemeye geçiş; web video adresi doğrulama.
- Telefon (390×844) ve masaüstü (1280×800) etkileşim testlerinde kutu sekmesi, yön/sayı tuşları ve cihaz listesi sınandı. TV işaretçisi kapalıyken kutu sayı tuşunun doğru adrese gittiği doğrulandı.
- Gerçek Android emülatöründe ve macOS Flutter görüntüleyicisinde açık temalı yeni kutu kumandası kontrol edildi. Küçük ekrandaki oynatma düğmesinin yazı taşması düzeltildi ve tekrar görüntülendi. Görseller sentetik test verisi olarak etiketlidir; üretim giriş noktası bu verileri kullanmaz.
- Android release ARM64 APK: v2 imzası ve sürüm kodu 2022 doğrulandı; QA test verisi içermez. 20.322.039 bayt APK Faturabot tarafından kabul edildi.
- Gerçek LG / Android TV kutularıyla çoklu kutu, güç değişikliği, adres değişikliği ve video oynatma uçtan uca bu aktarımda denenmedi. iPhone sonuçları bu platformların gerçek cihaz doğrulaması sayılmaz.

## Yayımlanan 22. sürüm paketleri

Kaynak: `cdb055668d3f71175982eee5b96e3f85f76ce674`. [Sürüm ve indirmeler](https://github.com/ertugrulerzin/LGKumanda/releases/tag/v1.0.0-preview.22).

- ARM64 APK: 20.322.039 bayt; evrensel APK: 57.340.725 bayt. Her ikisi sürüm kodu 2022, sürüm adı 1.0.0 ve aynı v2 imzaya sahiptir. Evrensel paket ARM32, ARM64 ve x86_64 içerir; işlev farkı yoktur.
- macOS 1.0.0 (22): uygulama ve Flutter çalıştırılabilir dosyalarında x86_64 + arm64 doğrulandı. `codesign --verify --deep --strict` başarılı; ad-hoc imza, Developer ID veya noter onayı değildir. `hdiutil verify` DMG için başarılıdır. Üretim uygulamasında sentetik QA cihaz verisi bulunmaz.
- [Üç platformun CI çalışması](https://github.com/ertugrulerzin/LGKumanda/actions/runs/43959576576): Android, macOS ve Windows başarılı. Yayımlanan Windows EXE bu kaynak çalışmasının çıktısıdır; gerçek kurulum sessizce yapıldı, uygulama beş saniye çalışır durumda kaldı ve kaldırıldı.
- Yayımlanan Android ve macOS paketleri yerel release derlemeleridir. Dört paket için SHA-256 özetleri sürüme eklenmiştir.
- Android ARM64 APK Faturabot'a gönderildi; Telegram teslim yanıtı başarılı (mesaj 6618).

## Önceki paketlerin doğrulaması

# İlk önizlemenin doğrulama kapsamı

15 Kasım 2026 — `v1.0.0-preview.1`. Ortak uygulama kodu: `1ac9186`. Windows çalışma zamanı paketleme düzeltmesi: `527fd1d`.

## Üçüncü önizleme (`v1.0.0-preview.3`)

15 Kasım 2026 — kaynak `13859ca`, CI çalıştırması `43742390529`.

- Düzeltme: 1311 açıklama portu kapalı webOS TV’ler (ör. OLED55C64LA) ağ aramasında bulunamıyordu. Arama artık 3001 portundaki LG imzalı TLS sertifikasına da bakıyor.
- `flutter test` 23 test (yeni: LG sertifika tanıma). Canlı sertifika testi gerçek TV’ye karşı geçti.
- Android telefonda (yerel arm64 release derlemesi) “Ağda LG TV ara” TV’yi buldu ve bağlandı; kullanıcı onayladı.
- Paketler CI’da derlendi; yayımlanan paketlere ayrıca elle cihaz kurulumu yapılmadı.

## İkinci önizleme (`v1.0.0-preview.2`)

15 Kasım 2026 — kaynak `0eef978`, CI çalıştırması `43737861834`.

- Yeni: Tivibu gibi Android TV kutularının Wi-Fi ile kumandası (Android TV Remote v2: 6467 eşleştirme, 6466 kumanda).
- `flutter analyze` temiz; `flutter test` 21 test (protokol çerçeveleme, eşleştirme sırrı test vektörü, sertifika üretimi ve SecurityContext kabulü, tuş eşleme).
- Gerçek Tivibu kutusunda Mac’ten Flutter istemcisiyle eşleştirme (kod `8D417A`) ve tuş gönderimi hatasız tamamlandı. Tuşların kutu ekranındaki etkisi henüz kullanıcı tarafından onaylanmadı.
- Paketler CI’da derlendi; ayrıca elle cihaz kurulumu yapılmadı.

## Yerel kontroller

- `flutter analyze`: temiz.
- `flutter test`: 17 test; protokol, eşleştirme/onay ve güvenli saklama hatası, bağlantı yarışı ve zaman aşımı, sertifika kapsamı, HDMI yönlendirmesi, yerel ağ izni reddi, keşif XML'i, URL doğrulama ve Wake-on-LAN paketi.
- Arayüz testleri: 390×844 ve 1280×800 boyutlarında ilk kullanım, cihaz formu, bağlı kumanda ve metin gönderimi. Açılır menü odaklıyken tuşlar TV’ye gitmez; kumanda yüzeyinde yön tuşu, düğme odaklıyken Enter doğru hedefe gider. Uygulama araması veya HDMI seçimi Kanallar ekranına taşınmaz.
- Gerçek yerel TLS/WebSocket sunucusuyla geçici sertifika testi: ilk kullanım özeti, aynı özetle yeniden bağlanma, farklı özetin reddedilmesi ve mesaj alışverişi. Gerçek TV kullanılmadı; geçici anahtar/sertifika kaynak koduna alınmadı.
- macOS uygulaması ve Android APK derlendi. Android APK, API 35 emülatörüne kuruldu ve açıldı. Mac uygulaması ayrıca kullanıcının Mac Pro diye adlandırdığı M1 MacBook Pro’ya (macOS 27.0.1) `/Applications/LG Kumanda.app` olarak kuruldu; imza bütünlüğü ve çalışan süreç doğrulandı. Kurulum kontrolünde TV’ye bağlantı kurulmadı. Daha sonra kullanıcı Mac Pro’da web akışını denediğini, Google sonuçlarının TV ile Mac’te farklı göründüğünü bildirdi; bu, bütün TV komutlarının doğrulandığı anlamına gelmez.
- macOS yerel Flutter görüntüleyicisinden ve Android emülatöründen Türkçe açık tema ekranları kontrol edildi. Örnek TV verileri açıkça test verisi olarak etiketlidir; yayımlanan uygulamanın giriş noktası bu örnekleri kullanmaz.
- Android telefon (411×891), geniş düzen (1280×900) ve yazı boyutu 1.3 kontrolü; yazılım klavyesi açıkken metin alanı, gönder, Enter ve sil düğmeleri erişilebilir. Emülatör boyutu/yazı ayarı kontrol sonrasında geri alındı.
- Yerel DMG bütünlüğü ve uygulamanın ad-hoc imza bütünlüğü kontrol edildi. Bu, Developer ID imzası veya noter onayı değildir.

## İşletim sistemlerine göre derleme

| Paket | Kaynak / kontrol |
| --- | --- |
| Android APK, macOS DMG | Ortak uygulama kodu `1ac9186`; [Mac ve Android analiz/test/derleme çalışması](https://github.com/ertugrulerzin/LGKumanda/actions/runs/43728947665). |
| Windows kurulum EXE | Aynı ortak uygulama kodu ve Windows'a özgü `527fd1d` paketleme düzeltmesi; [Windows analiz/test/derleme/kurulum çalışması](https://github.com/ertugrulerzin/LGKumanda/actions/runs/43730468882). |

Windows adımı gerçek paketi sessizce kurar, EXE/Flutter/Visual C++ çalışma zamanı/veri dosyalarını kontrol eder ve kaldırır. Ayrı, elle başlatılan `Windows installer structure check` iş akışı yalnızca sentetik dosyalarla kurulum betiğini hızlı kontrol eder; bu dosyalar hiçbir zaman yayımlanmaz ve gerçek uygulama kontrolünün yerine geçmez.

## Henüz doğrulanmayanlar

Bu yeni uygulamanın üç platformda gerçek LG TV ile uçtan uca eşleştirmesi ve bütün komutları; fiziksel Android cihaz ergonomisi; Android 17 yerel ağ izin penceresinin cihaz üzerindeki davranışı; Windows görünümü/erişilebilirlik ve gerçek cihaz etkileşimi; sitelere göre tarayıcı/video/iframe uyumu; her TV’de uyandırma ve HDMI-CEC.

Windows için derleme ve paket kontrolü, görsel inceleme yerine geçmez. iPhone’un önceki canlı TV sonuçları yeni platformların testi olarak sunulmaz.

Mevcut `DESIGN.md` korunmuştur. Eski iOS tasarım yan dosyası `.impeccable/design.json` ile metin arasındaki önceden var olan farklar bu çalışmada değiştirilmemiştir; uygulama bu yerel yan dosyayı kullanmaz.
