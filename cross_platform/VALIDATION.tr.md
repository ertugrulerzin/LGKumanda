# İlk önizlemenin doğrulama kapsamı

15 Kasım 2026 — `v1.0.0-preview.1`. Ortak uygulama kodu: `1ac9186`. Windows çalışma zamanı paketleme düzeltmesi: `527fd1d`.

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
