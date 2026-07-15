# CALP — Marka & Alan Adı Kontrol Listesi (Yayın Kapısı)

> SF-1001 çıktısı. Bu liste tamamlanmadan **public release işaretlenemez**.
> Karar kaydı (ROADMAP FAZ 10, 2026-07-13): Çalışma markası **Calp**,
> tasarım dili "visual nutrition intelligence" — düz, tipografi öncelikli.
> Foodvisor ile kategori/isim yakınlığı nedeniyle resmi kontrol yayın engelidir.

## 1. İsim / marka kullanılabilirliği
- [ ] App Store'da "Calp" adının benzersizliği (App Store Connect ad rezervasyonu)
- [ ] Foodvisor / Foodvisor benzeri isimlerle karışıklık riski hukuki değerlendirme
- [ ] Türkiye (TÜRKPATENT) marka ön araştırması — 9. sınıf (yazılım) / 42. sınıf (SaaS)
- [ ] ABD USPTO / EUIPO ön araştırması (uluslararası yayın hedefleniyorsa)
- [ ] Sosyal medya kullanıcı adı uygunluğu (@calp)

## 2. Alan adı
- [ ] `calp.app` sahipliği/satın alımı (yasal linkler bu domaine işaret ediyor:
      `NutritionConstants.LegalLinks` → `https://calp.app/privacy`, `/terms`)
- [ ] Gizlilik Politikası ve Kullanım Koşulları sayfaları gerçek içerikle yayında
- [ ] Destek e-postası çalışır durumda (şu an `av.fatihdisci@gmail.com`; markalı
      `destek@calp.app` düşünülebilir — `ContentView` mailto satırı)

## 3. Uygulama içi marka yüzeyi (kod tarafı — TAMAM)
- [x] `Info.plist` `CFBundleDisplayName` = **Calp**
- [x] Kamera/fotoğraf purpose string'leri Calp adını kullanıyor
- [x] Yasal linkler `calp.app` domainine işaret ediyor
- [x] Destek e-postası konusu "Calp Geri Bildirim v{sürüm}"
- [x] App icon `AppIcon-1024.png` set'e yerleşik (kırık `C` master), tek 1024 boyut,
      Xcode auto-generate; dosyada rounded-square/gradient/gölge yok (maske uygulamada)
- [x] Düz Calp renk paleti (domates kırmızısı vurgu) tüm renk asset'lerinde

## 4. Süreklilik (2026-07-15: eski marka → Calp geçişi) <!-- brand-keep -->
<!-- Geçmiş: Calorisor → Calp (bundle/namespace) — brand-keep -->
### 4a. Geçiş kayıtları <!-- brand-keep -->
> Rename geçmişi (yalnızca tarihsel kayıt): Sofra → Calorisor → Calp. <!-- brand-keep -->
- [x] Bundle ID `com.fatih.calorisor` → `com.fatih.calp` (ASC yayın öncesi) <!-- brand-keep -->
- [x] Widget bundle ID → `com.fatih.calp.widget`
- [x] URL scheme `calp://` (eski `calorisor://` tamamen kaldırıldı) <!-- brand-keep -->
- [x] App Group / CloudKit container → `group.com.fatih.calp` / `iCloud.com.fatih.calp`
- [x] Keychain servisi + widget kind → `com.fatih.calp*`
- [x] StoreKit product ID'leri → `com.fatih.calp.monthly/annual`; eski
      `com.fatih.calorisor.*` legacy uyumluluk için proxy allowlist'inde <!-- brand-keep -->
- [x] UserDefaults key prefix → `calp.*`
- [x] Proxy: kanonik `x-calp-*` header + `CALP_CLIENT_KEY` / `CALP_DAILY_COST_ALERT_MICROUSD`;
      eski `x-calorisor-*` header ve `CALORISOR_*` env geçiş fallback'i olarak korunuyor <!-- brand-keep -->
- [x] Redis yazımları `calp:*`; entitlement cache eski `calorisor:*` anahtarını TTL süresince dual-read ediyor <!-- brand-keep -->
- [x] Tasarım sistemi namespace: `SofraTypography → CalpTypography`, `.sofraTitle → .calpTitle`, `SofraPressButtonStyle → CalpPressButtonStyle` <!-- brand-keep -->
- [x] SwiftData model adları korundu (iç mimari; marka içermiyor)
- [x] `project.yml` + `Calp.xcodeproj` `PRODUCT_NAME` → `Calp` (app + widget)

## 5. App Store metadata (yayın öncesi)
- [ ] App Store listing başlığı/altbaşlığı Calp
- [ ] Ekran görüntüleri yeni marka/renk ile (SF-1008)
- [ ] Privacy nutrition label metni (`proxy/README.md` taslağı ile senkron)
- [ ] Abonelik ürün görünen adları App Store Connect'te Calp

---
**Durum:** Kod tarafı marka yüzeyi ve süreklilik hazır. Kalan maddeler
(isim/domain/hukuk/metadata) Fatih'in hesap ve hukuki kontrolünü bekliyor.
