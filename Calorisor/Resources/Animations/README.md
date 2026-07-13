# Lottie Animations

Bu klasöre Bodymovin / Lottie `.json` dosyalarını bırak (uzantısız isimle bakılır).
`SofraLottieView` initializer'ına sadece **bare name** ver, uzantı verme.

## Örnek

`sofra_empty_plate.json` adlı dosyayı buraya koy → SwiftUI'da:

```swift
SofraLottieView("sofra_empty_plate", speed: 0.85) {
    // Asset yoksa / yüklenemedi ise gösterilecek fallback
    SofraIconView(icon: .sofra, size: 44)
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

## Mevcut kullanım yerleri (Faz 2 itibarıyla)

| View                       | Asset adı                 | speed | Not |
|----------------------------|---------------------------|-------|-----|
| `DailyView.emptyMealsCard` | `sofra_empty_plate`       | 0.85  | "Bugün henüz öğün eklemedin" ekranı |

Asset bulunmadığında boş durum `SofraPulseShine` ile 1,8 saniyelik sakin bir
nefes animasyonuna düşer. Wrapper kaldırılmamalı; aşağıdaki dosyalardan biri
eklendiğinde aynı çağrı otomatik olarak Lottie'yi kullanır.

## Beklenen asset adları

- [ ] `sofra_empty_plate.json` — boş günlük görünümü
- [ ] `sofra_paywall_hero.json` — paywall hero animasyonu (tabak breathing)
- [ ] `sofra_onboarding_intro.json` — onboarding ilk ekran
- [ ] `sofra_celebration_burst` — ilk ücretli gün özeti kutlaması (nadir)
