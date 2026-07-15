# Lottie Animations

Bu klasöre Bodymovin / Lottie `.json` dosyalarını bırak (uzantısız isimle bakılır).
`CalpLottieView` initializer'ına sadece **bare name** ver, uzantı verme.

## Örnek

`calp_empty_plate.json` adlı dosyayı buraya koy → SwiftUI'da:

```swift
CalpLottieView("calp_empty_plate", speed: 0.85) {
    // Asset yoksa / yüklenemedi ise gösterilecek fallback
    CalpIconView(icon: .calp, size: 44)
        .foregroundStyle(Color.accentFill)
}
```

`xcodegen generate` çalıştırınca bu klasör otomatik bundle resource olarak
eklenir, ek bir build config gerekmez.

## Asset yönergeleri (marka uyumu için)

- **Stil:** Line drawing (1.5px stroke), `currentColor` renkler. Soft, sessiz, "nefes" hissi.
- **Süre:** 3-5s döngü (idle animasyon), spike/çarpışma yok.
- **Renk paleti:** `accentFill` (#B87333) veya `textMuted` (#6E6659) — sıcak bej sayfada erimiyor.
- **Canvas:** 256x256 veya 512x512 kare. Aksi halde `aspectRatio` bozar.
- **Boyut:** Hedef slot'tan 2x büyük olabilir (Retina için), daha büyüğü boyutu şişirir.

## Tooling

- **LottieFiles Editor** (lottiefiles.com): AE olmadan küçük animasyonlar üretmek için.
- **Adobe After Effects + Bodymovin plugini**: tasarımcı varsa, bu tercih.
- **Lottie iOS Previewer** (App Store): telefonda canlı test için.

## Mevcut durum (görsel farklılaştırma geçişi sonrası)

Şu an marka onaylı **hiçbir Lottie asset'i yok**, bu yüzden `CalpLottieView`
wrapper'ının **aktif tüketicisi yok**. Boş durumlar (ör. `DailyView.emptyMealsCard`,
`ResultView` "yemek bulunamadı") artık amaca özel **statik SwiftUI vektör**
kompozisyonları kullanıyor — Reduce Motion güvenli, eksik asset'e bağımlı değil ve
sonsuz "nefes" döngüsü içermiyor.

Wrapper **kaldırılmadı**: tek ve belgelenmiş gelecek entegrasyon noktası olarak
korunuyor. Marka onaylı bir `.json` bu klasöre eklendiğinde, yüksek değerli **tek**
bir ekran (aşağıdaki adaylardan biri) `CalpLottieView`'e geri bağlanır.

Uygun aday konumlar (en fazla ikisi):
- gerçek boş geçmiş durumu,
- ilk-tarama / onboarding açıklaması,
- nadir bir kilometre taşı,
- foto/yazı/ses yakınsamasını anlatan paywall değer görseli.

## Beklenen asset adları

- [ ] `calp_empty_plate.json` — boş günlük görünümü
- [ ] `calp_paywall_hero.json` — paywall hero animasyonu (tabak breathing)
- [ ] `calp_onboarding_intro.json` — onboarding ilk ekran
- [ ] `calp_celebration_burst` — ilk ücretli gün özeti kutlaması (nadir)
