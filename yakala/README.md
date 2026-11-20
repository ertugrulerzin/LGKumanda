# Yakala

Web sayfalarındaki videoları bulup indiren macOS uygulaması. Kumanda'dan ayrı bir projedir; bu depoda yalnızca klasör olarak durur.

## Nasıl çalışır?

1. Uygulamanın içindeki tarayıcıda (WebKit) videonun olduğu sayfayı aç ve videoyu oynat.
2. Sayfanın istediği video adresleri sağdaki **Bulunanlar** listesine düşer. HLS listelerinde kalite seçilebilir.
3. **İndir**'e bas. Dosya `İndirilenler` klasörüne MP4 olarak kaydedilir.

| Tür | Ne yapılır |
| --- | --- |
| HLS (`.m3u8`) | Parçalar 6'şar paralel indirilir. AES-128 şifreli parçalar çözülür, ayrı ses izi varsa birleştirilir, ffmpeg ile MP4'e çevrilir. |
| Canlı HLS | **Kaydet** ile kayıt başlar, **Kaydı bitir** ile MP4 olur. |
| Düz dosya (MP4, WebM, FLV, MOV) | Sunucu destekliyorsa 8 MB'lık parçalar hâlinde 4 paralel bağlantıyla indirilir. |
| Altyazı | HLS altyazı izleri ve sayfadaki `.vtt`/`.srt`/`<track>` dosyaları bulunur. MP4'e gömülür, yanına `.srt` olarak da kaydedilir. |
| Kaldığı yerden devam | İnen parçalar `~/Library/Application Support/Yakala` altında saklanır. Duraklatılan ya da uygulama kapanınca yarım kalan indirmeler aynı yerden sürer. |
| Geçici hatalar | 429'da `Retry-After` kadar beklenir ve o siteye giden paralel bağlantı yarıya iner. Kopan bağlantı ve 5xx hatalarında indirme 6 kez, artan aralıklarla kendiliğinden yeniden dener. |

## Reklam engelleyici

Adres çubuğundaki kalkan düğmesi, AdGuard'ın Safari sürümüne benzer bir engelleyiciyi yönetir. EasyList, EasyPrivacy ve AdGuard Türkçe filtre listeleri indirilir, WebKit içerik kurallarına çevrilir (`Yakala/Engine/FilterConverter.swift`) ve engellemeyi doğrudan WebKit yapar: reklam/izleyici istekleri engellenir, reklam öğeleri gizlenir. Listeler 4 günde bir kendiliğinden güncellenir. Engelleyici tamamen ya da yalnızca geçerli site için kapatılabilir. Kullanıcı tıklamadan scriptlerin açtığı pop-up pencereler de engellenir.

Scriptlet, CSS enjeksiyonu ve genişletilmiş seçiciler (`#?#`, `#$#`, `#%#`) desteklenmez. Bu yüzden YouTube'un video içi reklamları gibi script tabanlı reklamlar engellenmeyebilir.

Video adresleri sayfanın `fetch`/`XHR` istekleri, `<video>`/`<source>` öğeleri ve kaynak zamanlama kayıtlarından yakalanır (`Yakala/UI/Sniffer.swift`). İndirme isteklerine tarayıcının çerezleri, `Referer` ve `User-Agent` bilgisi eklenir.

## Sınırlar

- DRM'li yayınlar (FairPlay, Widevine, SAMPLE-AES) indirilmez; uygulama bunu açıkça söyler.
- DASH (`.mpd`) henüz desteklenmiyor.
- Süreli imzalı adresler uygulama uzun süre kapalı kaldıktan sonra geçersizleşebilir; o durumda videoyu sayfadan yeniden yakalamak gerekir.
- Range desteklemeyen sunuculardan inen düz dosyalar baştan başlar.
- Adresi yakalanamayan videolar için oynatma tamponunu kaydetme (MSE kaydı) henüz yok.
- MPEG-TS'yi MP4'e çevirmek ve ayrı sesi birleştirmek için ffmpeg gerekir (`brew install ffmpeg`). ffmpeg yoksa tek izli indirmeler `.ts` ya da fMP4 olarak kaydedilir.
- İndirdiğin içeriğin haklarına ve sitenin kullanım koşullarına uymak senin sorumluluğundadır.

## Derleme ve test

```sh
cd yakala
xcodegen generate
xcodebuild -project Yakala.xcodeproj -scheme Yakala -destination 'platform=macOS' test
```

Entegrasyon testleri ffmpeg ile şifreli bir HLS akışı ve büyük bir MP4 üretir, bunları yerel bir Range sunucusundan (`YakalaTests/range_server.py`) sunar ve gerçek indiricilerle geri indirir. ffmpeg yoksa bu testler atlanır.
