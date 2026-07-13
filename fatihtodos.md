# Fatih — Yayına Çıkış To-Do (Sofra)

> Codex handoff'u + 7 gün ücretsiz deneme için App Store Connect adımları.
> Bu dosya, bilgisayar başına geçtiğinde elle yapacağın (Claude/Codex'in yapamadığı)
> hesap/kurulum işlerinin listesidir. Kod tarafı ROADMAP.md'de takip ediliyor.

## Mevcut durum (referans)
- **Branch:** `roadmap`, commit'ler local'de (pushlanmadı):
  - `ff4516d` — SF-1006 + SF-1007: EN/TR yerelleştirme altyapısı ve global dil politikası
  - `57bda90` — SF-1008: Global QA, erişilebilirlik ve yayın kapısı
  - Faz 10'un tüm kod yüzeyi tamam. 22+15 dosya değişti.
- **Test:** 80 test, 0 hata
- **Faz 10:** SF-1001…1008 arası tüm maddeler kod tarafında tamam.
  Kalan: gerçek cihaz QA, App Store Connect yapılandırması, marka/alan adı kontrolleri.
- **Yerel değişiklikler:** `Sofra/secrets.plist` ve `project.pbxproj` stash'te (main'den geçerken).

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
   Bu değer `CALORISOR_CLIENT_KEY` olacak.

## 3. Vercel projesini oluştur
1. Vercel'de GitHub'daki sofram reposunu içe aktar.
2. Root Directory olarak `proxy` seç.
3. Şu environment variable'ları ekle:
   - `OPENAI_API_KEY`
   - `CALORISOR_CLIENT_KEY`
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
- İlk istek: HTTP 200 ve `x-calorisor-cache: miss`
- Aynı istek tekrar: `x-calorisor-cache: hit`
- Yanlış istemci anahtarı: HTTP 401
- Arka arkaya 11 istek: son istek HTTP 429

## 5. Uygulamayı proxy'ye bağla
`Sofra/Info.plist` içinde:
- `AIProxyEndpointURL` → Vercel `/api/scan` adresi
- `AIProxyAPIKey` → oluşturduğun `CALORISOR_CLIENT_KEY`

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
   - App Group: `group.com.fatih.calorisor`
   - CloudKit container: `iCloud.com.fatih.calorisor`

## 7. App Store Connect abonelikleri
Aynı subscription group ("Sofra Premium") altında oluştur:
- `com.fatih.calorisor.monthly`
- `com.fatih.calorisor.annual`

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
- ✅ App Icon (1024×1024) yerleştirildi (`Sofra/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`)
- Gerçek gizlilik politikası ve kullanım koşulları URL'lerini sağla
  (`Sofra/Models/NutritionConstants.swift` → `LegalLinks` placeholder'ları → `calorisor.app`).
- **Gizlilik etiketi kararı:** Proxy, normalize analiz yanıtını 7 gün cache'lediği için
  doğrudan "veri toplanmıyor" seçmek riskli. Ya cache kaldırılmalı ya da
  "kullanıcıyla ilişkilendirilmeyen User Content" olarak beyan edilmeli.
- QA notlarını gönder (`PHASE_QA_NOTES.md` güncellendi, 2-dilli checklist hazır);
  hatalar düzeltilip ardından main merge/PR aşaması tamamlanır.

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
   (`com.fatih.calorisor.monthly`, `com.fatih.calorisor.annual`).
3. **Yıllık ürünü** (`com.fatih.calorisor.annual`) aç → **Introductory Offers → (+)**.
   - **Offer Type / Payment:** `Free` (Ücretsiz)
   - **Duration:** `1 Week` seç.
     - ⚠️ ASC'de "7 gün" diye bir seçenek YOKTUR; **1 hafta = 7 gündür**. Kod bunu
       "7 gün" olarak gösterir (P1W → 7 gün). "3 Days" seçme — o zaman uygulama "3 gün"
       yazar ve isteğin bozulur.
   - **Countries/Regions:** satışa açacağın tüm ülkeler (en azından Türkiye).
   - **Start Date:** bugünden; **End Date:** boş bırak (süresiz).
4. **Aylık ürüne** (`com.fatih.calorisor.monthly`) introductory offer **EKLEME** — aylıkta
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

---

# SF-1006/1007 SONRASI — YENİ EKLENENLER

## 10. Marka ve alan adı kontrolleri (CALORISOR_BRAND_CHECK.md)
Bu kontroller yapılmadan yayın onayı verilmez:
- [ ] App Store'da "Calorisor" isim müsaitliği kontrolü
- [ ] `calorisor.app` alan adı kaydı
- [ ] Privacy Policy sayfası yayında (`https://calorisor.app/privacy`)
- [ ] Terms of Use sayfası yayında (`https://calorisor.app/terms`)
- [ ] TURKPATENT marka araştırması (sınıf 9, 42)
- [ ] USPTO / EUIPO marka araştırması
- [ ] Foodvisor isim benzerliği hukuki değerlendirmesi
- [ ] Sosyal medya kullanıcı adı (@calorisor) kontrolü
- [ ] Destek e-postası (`destek@calorisor.app`) — şu an `av.fatihdisci@gmail.com`

## 11. App Store iki dilli metadata (TR + EN)
- [ ] App Store açıklaması (TR + EN)
- [ ] Anahtar kelimeler (TR + EN)
- [ ] Ekran görüntüleri: 6.7", 6.5", 5.5" — her boyut için TR ve EN set
- [ ] Abonelik ürün görünen adları: "Calorisor Pro Aylık" / "Calorisor Pro Yıllık" (ve İngilizce karşılıkları)
- [ ] Privacy nutrition label (App Store Connect)

## 12. Proxy prompt güncellemesi
- [ ] `proxy/prompts.ts`: yeni dil-aware prompt'larla Vercel'e deploy et
  - TR için mevcut prompt korundu (Turkish cuisine)
  - EN için yeni prompt (international foods, English units)
  - `proxy/api/scan.ts`: `household_unit` enum'ı genişletildi (17 birim)
- [ ] Deploy sonrası curl testini TR ve EN locale için tekrarla

## 13. Xcode'da yapılacaklar
- [ ] `DEVELOPMENT_TEAM` doldur → `xcodegen generate`
- [ ] `Localizable.xcstrings` Xcode'da build al — String Catalog'un derlenmesi gerek
- [ ] `Sofra/App/AppLanguage.swift` ve `Sofra/Resources/Localizable.xcstrings` Xcode projesine eklendi mi kontrol et
- [ ] Scheme'de StoreKit config'in bağlı olduğunu doğrula
- [ ] Widget target'ına `SofraIcon.swift` paylaşımı (marka logosu widget'ta) — ertelenmişti

## 14. İki dilli QA (güncellenmiş PHASE_QA_NOTES.md)
- [ ] TR tam tur: onboarding → kamera → analiz → sonuç → log → geçmiş → ayarlar → widget → silme
- [ ] EN tam tur: aynı akış, tüm metinler İngilizce olmalı
- [ ] VoiceOver: tüm ikon butonlar okunuyor, slider'lar değer söylüyor, dekoratif öğeler atlanıyor
- [ ] Light/dark mode: tüm ekranlar
- [ ] Dynamic Type en büyük ayar: metinler taşmıyor
- [ ] iPhone SE: Paywall sığıyor, sütunlar taşmıyor
- [ ] Gerçek cihaz ikon maskesi

## 15. Abonelik grubu isim güncellemesi
- Kod `Calorisor Pro` markasını kullanıyor. App Store Connect'teki "Sofra Premium" grubu → "Calorisor Pro" olarak güncellenmeli (ya da tam tersi, kod ASC'ye uyacak şekilde). Hangisi olursa olsun, kod ve ASC aynı olmalı.
