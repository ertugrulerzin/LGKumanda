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
- 18 Kasım: sürüme derleme 24 bağlandı. Gönderim iki uyum formu yüzünden
  engelli (güvenlik ve yapay zekâ içeriği; kullanıcı ASC'de dolduracak).
  Gönderim 9b52bbe2-… READY_FOR_REVIEW, içi boş.
- **Eksik:** incelemeye gönderme. ASC API `reviewSubmissions` 500 dönüyor; bir
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
  App settings > Add store). Kalan: App Privacy'yi reklam verileriyle güncelle,
  yaş anketinde advertising=true, PRIVACY.md, ödeme/vergi bilgisi (kullanıcı),
  derleme 25 → 1.1.

## Diğer

- Multicast entitlement talebi (PK7RAMVV73) Apple onayı bekliyor; onaylanınca
  `Configuration/Multicast.entitlements` eklenip yeni derleme çıkılacak.
- Tanıtım videosu: `ScreenshotTests.testDemoVideo` (önizleme modu, TV gerekmez);
  App Store ekran görüntüleri: `testAppStoreScreenshots` (6.9" simülatör,
  `simctl status_bar` 9:41).
- ASC yardımcıları: `node scripts/asc.mjs GET|POST|PATCH /v1|v2/...`.
