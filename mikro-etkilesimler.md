# Sofra — Mikro-Etkileşim Kataloğu

*Bu doküman detaylı SwiftUI prompt'u değildir. Agent'a ne zaman geçersek, buradaki her madde tek tek "şu ekranda şu tetikleyicide şu animasyon + şu haptic" formatında ayrı bir prompt satırına dönüşecek. Şimdilik referans/hafıza notu.*

## Genel prensip
Cal AI ve MFP'nin loading spinner + sert slide transition dilinin tam tersi: hiçbir yerde klasik spinner yok, geçişler kesintisiz ve organik (spring physics, düşük bounce), her onay hem görsel hem haptic.

## Ekran/aksiyon bazlı tetikleyiciler

**Fotoğraf çekildiğinde (kamera → analiz)**
- Deklanşör anında: kısa `.impact(light)` haptic + shutter flash (beyaz overlay 60ms fade)
- Analiz sırasında spinner yok — çekilen fotoğraf üzerinde tanınan öğeler tek tek, soldan sağa, hafif gecikmeli "keşfediliyor" hissiyle belirir (her öğe için ~150ms stagger, fade+scale 0.9→1)
- Analiz bitince: `.impact(medium)` haptic + sonuç kartlarının aşağıdan yukarı spring ile gelmesi

**Yemek eklendiğinde (logla butonu)**
- Dokunma anı: buton scale(0.96) + `.impact(medium)` haptic aynı anda (200ms spring geri dönüş)
- Onay: buton ikonunun checkmark'a morph olması (ayrı ikon swap değil, path morph — SF Symbols'ün content-transition'ı kullanılabilir), 400ms sonra ekran geçişi
- Günlük halka güncellenirken: halka değeri sayı sayarak artmaz, tek yumuşak arc animasyonuyla (ease-out, 500ms) yeni değere gider — ani zıplama yok

**Ekmek/çay hızlı sayaç dokunuşu**
- Her dokunuş: `.impact(light)` haptic + sayının kendi üstünde küçük bir "+1" ghost text'in yukarı doğru fade-out olması (Instagram like-count artışı hissi, ama abartısız, 400ms)
- 3 çayı geçince (günlük eşik): ikon rengi kademeli olarak aksan tonundan uyarı tonuna kaymaz — bunun yerine haftalık özet ekranında pasif bilgi olarak görünür (anlık utandırma yok, sadece veri)

**Tencere kalibrasyonu kaydedildiğinde**
- "Bu evde böyle yapılır" onayı sonrası: kısa bir "öğrenildi" mikro-animasyonu — küçük bir etiket ikonunun karta iliştirilmesi gibi (pin-drop hissi, spring overshoot burada bilinçli olarak biraz daha belirgin, çünkü bu nadir/özel bir aksiyon)

**Widget'tan ana ekrana dönüş**
- Vakit'teki widget deneyiminin buraya taşınması: widget'a dokunma → app açılışında halka zaten doğru değerde, ayrıca bir yükleme durumu görünmemeli (state widget'tan aktarılır, sıfırdan çizilmez)

**Sofra Modu (v1.1) — sofra fotoğrafı analiz sonucu**
- Sofradaki her kalem tek tek "kaşif" animasyonuyla belirir (yukarıdaki analiz mantığıyla aynı, ama bu sefer çoklu kalem — stagger biraz daha uzun, 200ms/öğe)
- Kullanıcı "2 kepçe" gibi porsiyon seçince: seçilen porsiyon ikonunun (kepçe/dilim/kaşık — az önce ürettiğimiz SVG set) kısa bir "dolma" animasyonu (fill 0→1, 300ms) ile onaylanması

## Haptic sözlüğü (tutarlılık için)
- `light` — sayaç dokunuşları, hızlı onaylar
- `medium` — logla/kaydet aksiyonları, ekran geçişi tetikleyen aksiyonlar
- `notification(success)` — sadece nadir/önemli anlar: onboarding tamamlama, tencere kalibrasyonu kaydetme, deneme→ücretli dönüşüm sonrası ilk gün özeti
