# CALORISOR — Marka & Alan Adı Kontrol Listesi (Yayın Kapısı)

> SF-1001 çıktısı. Bu liste tamamlanmadan **public release işaretlenemez**.
> Karar kaydı (ROADMAP FAZ 10, 2026-07-13): Çalışma markası **Calorisor**,
> tasarım dili "visual nutrition intelligence" — düz, tipografi öncelikli.
> Foodvisor ile kategori/isim yakınlığı nedeniyle resmi kontrol yayın engelidir.

## 1. İsim / marka kullanılabilirliği
- [ ] App Store'da "Calorisor" adının benzersizliği (App Store Connect ad rezervasyonu)
- [ ] Foodvisor / Foodvisor benzeri isimlerle karışıklık riski hukuki değerlendirme
- [ ] Türkiye (TÜRKPATENT) marka ön araştırması — 9. sınıf (yazılım) / 42. sınıf (SaaS)
- [ ] ABD USPTO / EUIPO ön araştırması (uluslararası yayın hedefleniyorsa)
- [ ] Sosyal medya kullanıcı adı uygunluğu (@calorisor)

## 2. Alan adı
- [ ] `calorisor.app` sahipliği/satın alımı (yasal linkler bu domaine işaret ediyor:
      `NutritionConstants.LegalLinks` → `https://calorisor.app/privacy`, `/terms`)
- [ ] Gizlilik Politikası ve Kullanım Koşulları sayfaları gerçek içerikle yayında
- [ ] Destek e-postası çalışır durumda (şu an `av.fatihdisci@gmail.com`; markalı
      `destek@calorisor.app` düşünülebilir — `ContentView` mailto satırı)

## 3. Uygulama içi marka yüzeyi (kod tarafı — TAMAM)
- [x] `Info.plist` `CFBundleDisplayName` = **Calorisor**
- [x] Kamera/fotoğraf purpose string'leri Calorisor adını kullanıyor
- [x] Yasal linkler `calorisor.app` domainine işaret ediyor
- [x] Destek e-postası konusu "Calorisor Geri Bildirim v{sürüm}"
- [x] App icon `AppIcon-1024.png` set'e yerleşik (kırık `C` master), tek 1024 boyut,
      Xcode auto-generate; dosyada rounded-square/gradient/gölge yok (maske uygulamada)
- [x] Düz Calorisor renk paleti (domates kırmızısı vurgu) tüm renk asset'lerinde

## 4. Süreklilik (DEĞİŞMEDİ — kasıtlı)
- [x] Bundle ID `com.fatih.sofra` korundu
- [x] URL scheme `sofra://` korundu (widget deep-link)
- [x] CloudKit container / App Group korundu
- [x] StoreKit product ID'leri (`SofraProductID`) korundu
- [x] SwiftData model adları korundu
- [x] `project.yml` `PRODUCT_NAME` internal olarak "Sofra" (kullanıcıya görünmez;
      home-screen etiketi `CFBundleDisplayName`=Calorisor'dan gelir)

## 5. App Store metadata (yayın öncesi)
- [ ] App Store listing başlığı/altbaşlığı Calorisor
- [ ] Ekran görüntüleri yeni marka/renk ile (SF-1008)
- [ ] Privacy nutrition label metni (`proxy/README.md` taslağı ile senkron)
- [ ] Abonelik ürün görünen adları App Store Connect'te Calorisor

---
**Durum:** Kod tarafı marka yüzeyi ve süreklilik hazır. Kalan maddeler
(isim/domain/hukuk/metadata) Fatih'in hesap ve hukuki kontrolünü bekliyor.
