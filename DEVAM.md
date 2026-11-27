# Devam notu (17 Kasım 2026)

Kaldığımız yer ve sıradaki işler. Yeni oturumda önce bunu oku.

## App Store 1.0 (reklamsız)

- Mağaza adı: "Kumanda – webOS TV için" (tr), "Kumanda – Remote for webOS TV" (en-US).
  Ana ekran adı "Kumanda".
- Hazır: açıklamalar, anahtar kelimeler, alt başlık, destek ve gizlilik bağlantısı,
  5 ekran görüntüsü (6.9", tr + en-US), kategori Yardımcı Programlar / Eğlence,
  ücretsiz, 175 ülke, telif, yaş anketi (sınırsız web erişimi = evet),
  App Privacy "Data Not Collected" (yayınlandı), inceleme notu ve iletişim bilgisi,
  derleme 1.0 (23) sürüme bağlı, yayın şekli: elle (manual release).
- 18 Kasım: 1.0 (24) incelemeye gönderildi (WAITING_FOR_REVIEW, gönderim
  9b52bbe2-…). Engel olan iki uyum formu (güvenlik değerlendirmesi, AIGC) yalnızca
  Çin anakarası içindi; kullanıcı onayıyla Çin yayından çıkarıldı (174 ülke). ASC API `reviewSubmissions` 500 dönüyor; bir
  READY_FOR_REVIEW gönderimi oluşmuş olabilir (9b52bbe2-e523-4652-a7ce-0998cddc75e3).
  Arka planda `scratchpad/store/submitloop.py` 1 saat denedi; durum
  `GET /v1/appStoreVersions/8eae16a2-f5cf-47b0-9f9d-b900f004afea` ile kontrol edilir
  (PREPARE_FOR_SUBMISSION ise gönderilmedi).
- Kullanıcı App Store Connect'e web'den giriş yapamıyor (iCloud çalışıyor).
  Derleme 16 Kasım'da kabul edildiği için üyelik aktif. Sıradaki kontrol:
  developer.apple.com/account girişi ve bekleyen sözleşme (Agreements) uyarısı;
  giriş ekranındaki hata mesajı kullanıcıdan istenecek.
- İnceleme için kullanıcının gerçek TV ile çekeceği video önerildi (isteğe bağlı).

## 1.1: banner reklam (kod hazır, e71f884)

- `LGKumanda/Core/Ads.swift`: Google Mobile Ads + UMP onay formu; sekme çubuğu
  üstünde uyarlanabilir banner (Kumanda, Uygulamalar, Kanallar, Cihazlar).
  Klavye ve tarayıcıda reklam yok. Cihazlar'da "Reklam gizlilik seçenekleri".
- Release'de `KumandaBannerAdUnitID` boşken reklam yok; DEBUG Google test birimi.
  `GADApplicationIdentifier` şimdilik Google örnek kimliği.
- AdMob hesabı açıldı (18 Kasım; Google hesabı incelemede, ≤24 saat). Uygulama
  "Kumanda" iOS: `ca-app-pub-3117486801133085~3216899581`, banner birimi
  `ca-app-pub-3117486801133085/5570445232`; ikisi de project.yml'de.
  AdMob, uygulama App Store'da yayınlanınca mağazaya bağlanmalı (Apps > Kumanda >
  App settings > Add store).
- 1.1 (25) yüklendi (18 Kasım). TestFlight kurulumları Google test birimini
  kullanır (sandbox makbuzu); App Store kurulumu gerçek birimi. PRIVACY.md reklam
  bölümüyle güncellendi.
- Kalan (1.0 incelemesi bitince, ASC'de yeni sürüm açılabildiğinde): 1.1 sürümünü
  oluştur, derleme 25'i bağla, App Privacy'yi reklam verileriyle güncelle (web
  arayüzü), yaş anketinde advertising=true, "Yenilikler" metni, incelemeye gönder.
  Ödeme/vergi bilgisi kullanıcıda.

## Diğer

- Multicast entitlement (PK7RAMVV73) 20 Kasım'da onaylandı: App ID'de açıldı, yeni App Store profili
  "LG Kumanda App Store Multicast" (eskisi geçersiz), `CODE_SIGN_ENTITLEMENTS` project.yml'de. Dışa aktarma: `build/TestFlight/opts-26.plist`.
- Klavye: webOS `insertText` `"replace": 0` ile hiç yanıt vermiyor (TV tarayıcısında test edildi); `false` gönderiliyor.
  1.1 (26) TestFlight'a yüklendi.
- Tanıtım videosu: `ScreenshotTests.testDemoVideo` (önizleme modu, TV gerekmez);
  App Store ekran görüntüleri: `testAppStoreScreenshots` (6.9" simülatör,
  `simctl status_bar` 9:41).
- ASC yardımcıları: `node scripts/asc.mjs GET|POST|PATCH /v1|v2/...`.

## 27 Kasım 2026 — 1.0 onaylandı ve yayınlandı
- Apple 1.0 (29)'u onayladı (manuel yayın). 27 Kasım'da API ile yayınlandı: READY_FOR_SALE.
- 27 Kasım 18:28'de TR mağazada göründü. 28 Kasım: AdMob iOS uygulaması App Store kaydına bağlandı (Add store kaydedildi). Android Play'de olmadığı için bağlanmadı.
- AdMob doğrulaması app-ads.txt bekliyor: dosya https://ertugrulerzin.github.io/app-ads.txt adresinde yayında. Mağazada pazarlama URL'si boş olduğu için AdMob bulamıyor; 1.1'de marketingUrl = https://ertugrulerzin.github.io (tr, en). 1.1 yayınlanınca AdMob > Apps > Kumanda iOS > Check for updates.
- 1.1 ASC'de hazırlanıyor (PREPARE_FOR_SUBMISSION, derleme 30, manuel yayın): Yenilikler metni (tr, en), marketingUrl, yaş anketinde advertising=true tamam. kumanda-app/PRIVACY.md reklam bölümüyle güncellendi.
- 1.1 gönderiminden önce kalan: App Privacy'yi reklam verileriyle güncellemek (web arayüzü, kullanıcı); AdMob hesabının yeniden incelenmesini istemek (kullanıcı). Sonra incelemeye gönder.

## 26 Kasım 2026 — AdMob reddi
- AdMob hesabı (pub-3117486801133085) 25 Kasım'da e-postayla reddedildi: "program kriterlerine uygun değil", gerekçe yok. Panelde iki uygulama "Add store" bekliyor; büyük olasılıkla yayında uygulama olmadığı için.
- Yapılacak: 1.0 App Store'da yayınlanınca AdMob > Apps > Kumanda iOS > Add store ile App Store kaydını bağla, sonra hesabın yeniden incelenmesini iste. Onay gelene kadar 1.1'in banner reklamları boş kalır.

## 25 Kasım 2026 — 5.2.1 ikinci red
- Apple 1.0 (29)'u yine 5.2.1 ile reddetti ("LG TV içeriği veya LG donanımını kontrol etme"). Uygulama, metinler ve ekran görüntüleri temizdi. LG yalnızca mağazadaki destek ve gizlilik bağlantılarında kalmıştı: bu deponun adı (LGKumanda), tanımı ve PRIVACY.md'si.
- Markasız yeni herkese açık depo açıldı: github.com/ertugrulerzin/kumanda-app (README = destek, PRIVACY.md; e-posta yok, iletişim Issues). Destek URL'si (tr, en) ve gizlilik URL'si (tr, en) oraya çevrildi.
- Apple'a cevap yazıldı ve 25 Kasım 18:28Z'de yeniden gönderildi: WAITING_FOR_REVIEW. 1.1'de de bu iki bağlantı kullanılmalı; 1.1 reklam içerdiği için kumanda-app/PRIVACY.md o sürümle birlikte güncellenmeli.
- Yine reddederse: Meet with Apple randevusu (salı/perşembe). Kalan olası işaret: uygulama renginin LG kırmızısına benzemesi.

## 23 Kasım 2026 — 5.2.1 (fikri mülkiyet) reddi ve yeniden gönderim
- Apple 1.0 (24)'ü 5.2.1 ile reddetti. Uygulamada "Ağda LG TV ara" ve "LG webOS" yazıları vardı. LG'den izin belgesi olmadığı için markalar kaldırıldı.
- Uygulama: LG, webOS, SIMPLINK, Android TV ve Google TV adları kullanıcıya görünen hiçbir metinde yok. Adı bilinmeyen TV "Akıllı TV", kutu "TV kutusu" olarak görünüyor.
- 1.0 (29) `release/1.0` dalında hazırlandı. Dal 1726ea5 + 945e143; build 24'ün reklamsız kodu.
- Mağaza: açıklama, anahtar kelimeler ve tanıtım metni (tr ve en) markasız. 6-cihazlar ekran görüntüsü yeniden çekildi. İnceleme notu da markasız.
- Apple'a cevap yazıldı ve 23 Kasım 17:53Z'de yeniden gönderildi: WAITING_FOR_REVIEW.
- Ana dalda (1.1) aynı metin değişiklikleri var. 1.1 (30) TestFlight iç ve dış gruplarda (23 Kasım). 1.1 mağaza açıklaması ve "Yenilikler" metni de markasız olmalı.

## 20 Kasım 2026 — 1.0 reddi ve yeniden gönderim
- Apple 1.0 (24)'ü reddetti: 5.2.5 (ad/alt başlıktaki "webOS" tvOS'a benziyor) ve 2.3.10 (alt başlıkta "Android").
- Ad/alt başlık markasız yapıldı: TR "Kumanda – TV Uzaktan Kumanda" / "Akıllı TV ve TV kutuları için";
  EN "Kumanda – TV Remote Control" / "For smart TVs and TV boxes". Açıklama ve anahtar kelimeler aynı.
- Aynı derleme (24) 20 Kasım 14:28Z'de yeniden gönderildi: WAITING_FOR_REVIEW.
- 1.1 için de ad/alt başlıkta webOS/Android kullanılmamalı.
