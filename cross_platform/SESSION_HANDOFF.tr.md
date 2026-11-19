# 22. sürüm aktarımı

17 Kasım 2026: iPhone 1.0 (22), `f9395b2`, Android/Mac/Windows ortak Flutter uygulamasına aktarıldı. Güncel çoklu kutu modeli ve sekmeler `lib/core/android_tv/box_client.dart`, `ui/remote.dart`, `ui/box_remote.dart` ve `ui/box_setup.dart` içindedir. Eski tek kutu kaydı otomatik korunur; eşleştirmeler cihazlar arasında taşınmaz.

TV gücü, uyandırma doğrulaması ve UUID/sertifika ile adres kurtarma `lib/core/tv_client.dart` içindedir. TV depolama kimliği adres değişse de aynı kalır; eski IP tabanlı anahtar adları korunur. Web video gözlem betiği `assets/web_video.js`, TV kaynak doğrulaması `core/web_video.dart` ve arayüzü `ui/browser.dart` içindedir. Video oynatma deneysel kalır; her sitede başarı iddiası yoktur.

Yerel kontroller: `flutter analyze`, `flutter test`, Android release APK ve macOS uygulaması. Windows paketi GitHub Actions'ta üretilip kurulumdan geçer. Ayrıntılar `VALIDATION.tr.md` dosyasında güncellenir. QA uygulaması `tool/native_preview.dart` yalnız bellek içi açıkça etiketli test verisi kullanır; üretim giriş noktası `lib/main.dart`tır.

## Önceki oturum notu (15 Kasım 2026, tarihsel)


15 Kasım 2026 tarihli `e7c7f488-c164-4bd7-8cb9-08b269c0fb7a` oturumunun LG Kumanda ile ilgili son bölümü incelendi. Özel oturum kayıtları bu depoya kopyalanmadı.

Son yayımlanan iPhone sürümü oturum kaydına göre **1.0 (11)**. TV’deki dokunmatik panelde sürekli fare hareketi, küçük adımlı hedefleme okları ve Tıkla düğmesi var. Kullanıcı bu sürümle videoyu başlatabildiğini bildirdi.

Son istek, bunu fareyi göstermeden yapabilmekti. Claude, LG tarayıcısına `javascript:` hedefiyle bir odak/gezinme betiği gönderme üzerinde çalışıyordu. Yön tuşları öğeyi çerçeveyle seçiyor; OK önce betiği hazırlıyor, ardından gerçek ENTER olayı gönderiyor. Cross-origin iframe odağı tuşları yuttuğundan, iframe’e odak vermeden yalnızca çerçeveleme değişikliği yapılırken kota doldu. Bu son değişiklik için tamamlanmış bir canlı TV testi veya sonraki TestFlight yüklemesi kayıtta yok.

`LGKumanda/Core/WebFocus.swift` ve `TVClient.swift` bu çalışmayı içeriyor. iPhone kodu bu platform ekleme çalışmasında değiştirilmedi. Flutter sürümündeki `assets/web_focus.js`, bu Swift dosyasındaki betiğin kopyasıdır; TV’de web ekranından açılabilen, varsayılan kapalı **deneysel** seçenektir. Betiği değiştirirken iki kopyayı da güncelle.

Kesinleşmiş tercihler:

- Türkçe ve açık renkli arayüz.
- Varsayılan işaretçisiz yön/OK, ayrıca gerçek fare ve sessiz fare.
- AirPlay kullanıcı tarafından reddedildi; yeni platformlarda eklenmedi.
- TV’nin kendi tarayıcısında video başlatma; site ve iframe uyumluluğu için garanti verilmez.
- HDMI kutusuna komut iletimi SIMPLINK/HDMI-CEC desteğine bağlı; TV uygulamasıyla kutu kumandası birbirine karıştırılmaz.

Bir sonraki gerçek TV doğrulaması: işaretçisiz seçenek açıkken normal bağlantı, düğme, video ve cross-origin iframe içeren kontrollü sayfada yön/OK davranışını ölç. İframe’i doğrudan açmanın sitenin oturumunu/oynatıcısını bozabileceğini kontrol et. Bu aşamada gerçek TV’ye otomatik komut gönderilmedi.

## Google Play ve reklam (19 Kasım 2026)

- Play paket adı `com.ertugrul.kumanda` (Dart paket adı `lg_kumanda` olarak kaldı). Yayın
  imzası `~/.kumanda/kumanda-upload.jks`; parolalar `~/.kumanda/key.properties`
  içinde, `android/key.properties` ona bağlantıdır. İkisi de repoda değil. Anahtar
  yoksa release derlemesi debug anahtarıyla imzalanır (CI için).
- Android'de AdMob banner: uygulama `ca-app-pub-3117486801133085~3472120260`, birim
  `ca-app-pub-3117486801133085/2287031101`. Klavye sekmesinde ve tarayıcıda reklam
  yok; Mac/Windows'ta SDK hiç çalışmaz. Debug derlemeleri ve
  `--dart-define=KUMANDA_TEST_ADS=true` ile derlenen test sürümleri Google test
  birimini kullanır.
- Play test kanalı için: `flutter build appbundle --release --dart-define=KUMANDA_TEST_ADS=true`.
  Üretim için aynı komut, bayraksız.
