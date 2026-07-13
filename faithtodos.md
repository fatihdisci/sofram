# Fatih — Yayına Çıkış To-Do (Sofra)

> Codex handoff'u + 7 gün ücretsiz deneme için App Store Connect adımları.
> Bu dosya, bilgisayar başına geçtiğinde elle yapacağın (Claude/Codex'in yapamadığı)
> hesap/kurulum işlerinin listesidir. Kod tarafı ROADMAP.md'de takip ediliyor.

## Mevcut durum (referans)
- Commitler roadmap dalına pushlandı:
  - `617bf3f` — Roadmap uygulaması
  - `8d80e0e` — Yerel OpenAI anahtarını uygulama paketinden çıkaran güvenlik düzeltmesi
- 80 test, 0 hata; çalışma ağacı temiz; roadmap ile origin/roadmap aynı durumda.
- Bunların üstüne **paywall revizyonu** eklendi (bu oturum): scroll'suz tek ekran,
  koyu mod kontrast düzeltmesi, gerçek Pro'ya özel özellik listesi ve **yıllık planda
  7 gün ücretsiz deneme** (aylıkta deneme yok). Detay: aşağıdaki "7 Gün Ücretsiz Deneme" bölümü.

---

## 1. Dalı güncelle
```bash
cd /Users/fatihdisci/apps/sofram
git switch roadmap
git pull --ff-only origin roadmap
open Sofra.xcodeproj
```
Henüz main dalına merge etme.

## 2. Upstash Redis kur
1. Upstash'te yeni bir Redis veritabanı oluştur.
2. Şunları kaydet:
   - `UPSTASH_REDIS_REST_URL`
   - `UPSTASH_REDIS_REST_TOKEN`
3. Terminalde istemci anahtarı üret:
   ```bash
   openssl rand -hex 32
   ```
   Bu değer `SOFRA_CLIENT_KEY` olacak.

## 3. Vercel projesini oluştur
1. Vercel'de GitHub'daki sofram reposunu içe aktar.
2. Root Directory olarak `proxy` seç.
3. Şu environment variable'ları ekle:
   - `OPENAI_API_KEY`
   - `SOFRA_CLIENT_KEY`
   - `UPSTASH_REDIS_REST_URL`
   - `UPSTASH_REDIS_REST_TOKEN`
4. Production deploy başlat.
5. Oluşan adresi kaydet:
   ```
   https://PROJE-ADI.vercel.app/api/scan
   ```
OpenAI anahtarını kesinlikle Xcode'a veya Info.plist içine koyma.

## 4. Proxy'yi kontrol et
`proxy/README.md` içindeki curl testini çalıştır. Beklenen:
- İlk istek: HTTP 200 ve `x-sofra-cache: miss`
- Aynı istek tekrar: `x-sofra-cache: hit`
- Yanlış istemci anahtarı: HTTP 401
- Arka arkaya 11 istek: son istek HTTP 429

## 5. Uygulamayı proxy'ye bağla
`Sofra/Info.plist` içinde:
- `AIProxyEndpointURL` → Vercel `/api/scan` adresi
- `AIProxyAPIKey` → oluşturduğun `SOFRA_CLIENT_KEY`

Buraya OpenAI anahtarı değil, yalnızca paylaşılan istemci anahtarı yazılacak.
Bu değerleri herkese açık repoya commit etme.

## 6. Apple imzalama ayarları
1. Apple Developer Team ID'ni öğren.
2. `project.yml` içindeki boş `DEVELOPMENT_TEAM` değerini doldur.
3. Çalıştır:
   ```bash
   xcodegen generate
   ```
4. Xcode'da hem Sofra hem SofraWidgetExtension için aynı Team'i seç.
5. Şunların hatasız göründüğünü doğrula:
   - iCloud / CloudKit
   - Push Notifications
   - App Group: `group.com.fatih.sofra`
   - CloudKit container: `iCloud.com.fatih.sofra`

## 7. App Store Connect abonelikleri
Aynı subscription group ("Sofra Premium") altında oluştur:
- `com.fatih.sofra.monthly`
- `com.fatih.sofra.annual`

Her ikisine de uygun fiyat ve Türkçe lokalizasyon ekle.

> ⚠️ **DEĞİŞİKLİK:** Deneme politikası güncellendi. Eski plan "her iki plana 3 gün"
> idi; artık **yalnızca yıllık planda 7 gün ücretsiz deneme**, aylıkta deneme yok.
> Detaylı ASC adımları için aşağıdaki bölüme bak.

## 8. Gerçek cihaz QA turu
iPhone'u seçip uygulamayı çalıştır. `PHASE_QA_NOTES.md` listesini sırayla doldur:
1. Onboarding
2. Paywall geçişi
3. Kamera ve gerçek AI taraması
4. Sonuç düzeltme ve kaydetme
5. Kalori halkası
6. Quick-add
7. Geçmiş ve gün detayı
8. Hedef değiştirme
9. Ana ekran/kilit ekranı widget'ı
10. Abonelik yönetimi ve destek e-postası
11. Tüm verileri silme
12. Onboarding'e dönüş

Her satıra yalnız gözlemledikten sonra ✅ veya ❌ koy.

## 9. Son kalan kararlar
- Gerçek gizlilik politikası ve kullanım koşulları URL'lerini sağla
  (`Sofra/Models/NutritionConstants.swift` → `LegalLinks` placeholder'ları).
- 1024×1024 App Icon tasarımını yerleştir.
- **Gizlilik etiketi kararı:** Proxy, normalize analiz yanıtını 7 gün cache'lediği için
  doğrudan "veri toplanmıyor" seçmek riskli. Ya cache kaldırılmalı ya da
  "kullanıcıyla ilişkilendirilmeyen User Content" olarak beyan edilmeli.
- QA notlarını gönder; hatalar düzeltilip ardından main merge/PR aşaması tamamlanır.

---

# 7 GÜN ÜCRETSİZ DENEME — App Store Connect tarafında ne yapmalı

Kod ve yerel StoreKit config tarafı bu oturumda hazırlandı. Kalan iş yalnızca
**App Store Connect'te introductory offer tanımlamak**. Kod, deneme süresini üründen
**dinamik** okuyup gösterdiği için (`StoreKitManager.trialPeriodText`), ASC'de ne
ayarlarsan paywall onu yazar — bu yüzden ASC'yi 7 güne göre doğru kurman kritik.

## Kodda hazır olanlar (senin yapmana gerek yok — bilgi amaçlı)
- `Sofra/StoreKit/Products.storekit`: yıllık ürüne **P1W (1 hafta = 7 gün)** ücretsiz
  deneme; aylık üründe deneme yok. Ürün tipleri `autoRenewable`'a çevrildi.
- Scheme'e StoreKit config bağlandı (`project.yml` → `storeKitConfiguration`), böylece
  simülatörde **Xcode'dan çalıştırınca** (Cmd+R) fiyatlar ve deneme görünür.
  ⚠️ `xcrun simctl launch` ile açarsan StoreKit config uygulanmaz (fiyatlar "..." çıkar).
- `PaywallView`: deneme kopyası seçili plana göre dinamik — yıllık seçiliyken
  "7 gün ücretsiz deneme / Sonra ₺.../yıl" + CTA "7 Gün Ücretsiz Dene"; yıllık kartta
  "7 gün ücretsiz" rozeti; aylık seçilince deneme metni kaybolur, CTA "Abone Ol" olur.
- `PROJECT_CONTEXT.md`'de eski "3 günlük deneme" ifadesi kaldıysa güncelle (kod artık
  süreyi hardcode etmiyor; ASC + .storekit tek gerçek kaynak).

## App Store Connect adımları (7 gün deneme için)
1. **App Store Connect → Apps → Sofra → Subscriptions** (Monetization) bölümüne gir.
2. Subscription Group **"Sofra Premium"** yoksa oluştur; iki ürünü aynı grupta tut
   (`com.fatih.sofra.monthly`, `com.fatih.sofra.annual`).
3. **Yıllık ürünü** (`com.fatih.sofra.annual`) aç → **Introductory Offers → (+)**.
   - **Offer Type / Payment:** `Free` (Ücretsiz)
   - **Duration:** `1 Week` seç.
     - ⚠️ ASC'de "7 gün" diye bir seçenek YOKTUR; **1 hafta = 7 gündür**. Kod bunu
       "7 gün" olarak gösterir (P1W → 7 gün). "3 Days" seçme — o zaman uygulama "3 gün"
       yazar ve isteğin bozulur.
   - **Countries/Regions:** satışa açacağın tüm ülkeler (en azından Türkiye).
   - **Start Date:** bugünden; **End Date:** boş bırak (süresiz).
4. **Aylık ürüne** (`com.fatih.sofra.monthly`) introductory offer **EKLEME** — aylıkta
   deneme yok (kararlaştırılan politika).
5. Her iki ürünün de **Localization (tr-TR)**, **fiyat (price point)** ve
   **review screenshot/notes** alanlarını doldur; durum "Ready to Submit" olmalı.
6. Introductory offer, uygulama sürümüyle **birlikte** review'a gönderilir; ürünleri
   ilk sürümün "In-App Purchases and Subscriptions" bölümüne eklemeyi unutma.

## Eligibility (kimler denemeyi görür)
- Introductory offer, kullanıcı başına **subscription group içinde bir kez** geçerlidir.
- Uygulama `Product.SubscriptionInfo.isEligibleForIntroOffer` kontrol eder; daha önce bu
  grupta deneme/intro kullanmış kullanıcıya paywall denemeyi göstermez, doğrudan
  "Abone Ol" ve normal fiyat gösterir. Bu, Apple politikasının doğru davranışıdır.

## Doğrulama
- **Simülatör (yerel .storekit ile):** Xcode'da Sofra scheme'i + iPhone 16 simülatörü
  seçip **Cmd+R** ile çalıştır → Ayarlar → "Sofra Pro'ya Geç". Yıllık seçiliyken
  "7 gün ücretsiz deneme" ve gerçek fiyatlar (₺129,99 / ₺799,99) görünmeli.
  (`simctl launch` ile DEĞİL — config uygulanmaz.)
- **Sandbox (gerçek cihaz):** Settings → App Store → Sandbox Account ile test hesabı
  gir; gerçek deneme akışını (7 gün → yenileme) sandbox'ta hızlandırılmış sürelerle
  doğrula. `StoreKitManager.scheduleTrialEndNotification` deneme bitiminden 24 saat önce
  bildirim kurar — bunu da sandbox'ta gözlemle.
- **Terms/expiry:** Paywall footer'ındaki otomatik-yenileme metni de dinamik; yıllıkta
  "7 gün ücretsiz deneme sonunda ₺.../yıl olarak otomatik yenilenir" yazmalı.
