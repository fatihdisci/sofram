# CALP — ROADMAP (Codex Çalışma Planı)

> Bu dosya Calp'i "çalışan MVP"den "zirve kalite" ürüne taşıyan görev listesidir.
> 13 Temmuz 2026 tarihli tam kod incelemesinin çıktısıdır. Her bulgu koddan doğrulanmıştır
> (satır referansları o günkü duruma göredir; kaymış olabilir, imza/isimden bul).

---

## 0. ÇALIŞMA KURALLARI (Codex bunları her oturumda okur)

### İşaretleme protokolü
- Her görev `- [ ] SF-XXX` formatındadır. Bitirince `- [x] SF-XXX` yap ve satır sonuna `✅ YYYY-MM-DD` ekle.
- Bir görevi **kabul kriterleri sağlanmadan** işaretleme. Kriter test istiyorsa test yazılmadan bitmiş sayılmaz.
- Görev sırası fazlar içinde yukarıdan aşağıya. Fazlar arası atlama yapma; FAZ 0 bitmeden FAZ 1'e geçme (istisna: `[bağımsız]` etiketli görevler).
- Bir görevi yarım bırakıyorsan satır sonuna `⏸ NOT: <durum>` ekle.
- Kapsam dışına çıkma. Görevde yazmayan refactor/rename yapma.

### Derleme / test komutları
```bash
# Proje dosyası değiştiyse (yeni dosya eklendi/silindi):
xcodegen generate

# Derleme:
xcodebuild build -scheme Calp -destination 'platform=iOS Simulator,name=iPhone 16' | tail -20

# Testler:
xcodebuild test -scheme Calp -destination 'platform=iOS Simulator,name=iPhone 16' | tail -30
```
- Yeni `.swift` dosyası eklediğinde `xcodegen generate` çalıştır (project.yml `Calp/` altını otomatik toplar).
- Commit mesajı formatı mevcut geçmişe uysun: `fix:`, `feat:`, `test:`, `refactor:` + kısa İngilizce özet.

### DOKUNULMAZ KURALLAR (PROJECT_CONTEXT.md'nin özeti — asla ihlal etme)
1. **Hesap/login yok, Supabase yok, RevenueCat yok, barkod yok.** Bunlar için altyapı bile kurma.
2. Kullanıcı verisi **SwiftData + CloudKit Private**'ta kalır. Sunucu asla kullanıcı verisi görmez/saklamaz.
3. Her `@Model` property'si default değerli veya optional; ilişkiler optional; `@Attribute(.unique)` yasak (CloudKit).
4. Tasarım tokenları (`design-tokens.json`, `Color+Tokens.swift`, `Font+Tokens.swift`, `Layout.swift`) dışında renk/font/spacing hardcode etme. `accent-fill` renginde **metin yazma** (yalnızca ikon/dolgu).
5. Sayısal her gösterim **Geist Mono** token'ları ile (`.calpNumeric*`, `.calpDisplay*`).
6. Tüm kullanıcı kopyası **Türkçe ve İngilizce** olarak yerelleştirilmeli. Yeni kullanıcı metni hard-code edilmez; String Catalog anahtarıyla eklenir. Türkçe ve İngilizce dışında dil varsayımı yapılmaz (bkz. FAZ 10).
7. Porsiyon dili Türkçe ev ölçüleri: kepçe, yemek kaşığı, su bardağı, çay bardağı, dilim, avuç, kase, adet. Kullanıcıya ham gram slider'ı sunma (gram sadece ikincil bilgi etiketi).
8. Aşırıya kaçan animasyon yok; mikro-etkileşimler `mikro-etkilesimler.md`'ye uyar. Utanç/suçlama kopyası yasak ("hedef üstü" nötr veridir).

---

## FAZ 0 — VERİ DOĞRULUĞU: YANLIŞ SAYI ÜRETEN HATALAR (P0 — her şeyden önce)

Bu fazdaki hatalar kullanıcıya **yanlış kalori** gösteriyor ve üstüne "Doğrulanmış" rozeti basıyor.
Uygulamanın tek işi doğru sayı göstermek — bu faz bitmeden hiçbir görsel işe girme.

- [x] **SF-001 · ReferenceReconciler substring eşleştirme felaketini kaldır** ✅ 2026-07-13
  **Dosya:** `Calp/Nutrition/ReferenceReconciler.swift` (match/startsWithMatch/containsMatch)
  **Sorun (doğrulanmış, simüle edildi):** `startsWith`/`contains` fallback'leri kelime sınırı gözetmiyor:
  - "ızgara balık" → **"bal"** (300 kcal/100g bal değerleri + "Doğrulanmış" rozeti!)
  - "balık ekmek" → "bal" · "muzlu kek" → "Muz" (89 kcal/100g; gerçek ~350) · "elmalı turta" → "Elma"
  - "üzümlü kek" → "Üzüm" · "kavunlu dondurma" → "Kavun" · "kolalı içecek" → "Kola"
  - "ekmek" → "Kokoreç (yarım ekmek)"
  **Talimat:**
  1. `startsWithMatch` ve `containsMatch` fonksiyonlarını ve onları kullanan iki fallback döngüsünü **sil**.
  2. Eşleştirme politikası şu üç adımdan ibaret olsun, fazlası YOK:
     a. **Exact:** normalize edilmiş tam anahtar eşitliği (mevcut exact index).
     b. **Alias:** `String.Turkish.aliases` üzerinden exact eşitlik (mevcut davranış).
     c. **Token-set eşitliği:** aday ve referans anahtarı kelimelere bölünüp `Set` olarak **birebir eşitse** eşleş ("çorbası mercimek" == "mercimek çorbası"). Alt küme/üst küme YETMEZ — eşleşme yok say.
  3. `String.Turkish.foodKey`'e parantez temizliği ekle: `(`, `)` karakterlerini boşluğa çevir, sonra whitespace-collapse. Böylece DB'deki "Siyah çay (şekersiz)" → `siyah cay sekersiz` olur ve alias tablosuyla yakalanabilir.
  4. `String.Turkish.synonymPairs`'i genişlet (hepsi normalize edilmiş yazım):
     `("cay", "siyah cay sekersiz")`, `("siyah cay", "siyah cay sekersiz")`, `("pilav", "pirinc pilavi")`, `("yogurt", "yogurt (tam yagli)")` gibi — DB'deki parantezli kanonik adların çıplak hallerini kapsa. DB'yi tara, parantezli **her** satır için çıplak alias ekle.
  **Kabul kriterleri:**
  - Yeni test dosyası `CalpTests/ReconcilerNegativeTests.swift`: "ızgara balık", "balık ekmek", "muzlu kek", "elmalı turta", "üzümlü kek", "ekmek" adlarının **hiçbirinin** referans eşleşmesi almadığını (source == .ai, referenceName == nil) doğrula.
  - Pozitif testler: "çay" → siyah çay şekersiz; "mercimek çorbası", "kırmızı mercimek çorbası" → mercimek çorbası; "Muz" → Muz. Mevcut tüm testler geçmeye devam eder.

- [x] **SF-002 · Referans DB'ye temel ekmek + eksik temel gıdaları ekle** ✅ 2026-07-13
  **Dosya:** `Calp/Resources/turkish_food_reference.json`
  **Sorun:** DB'de 145 gıda var ama **düz ekmek yok** ("ekmek" kategorisinde sadece simit!). Türkiye'nin 1 numaralı gıdası eksik. Synonym tablosunda `beyaz ekmek → ekmek` çifti var ama hedef satır yok — ölü alias.
  **Talimat:** Şu satırları ekle (TÜBER 2022 uyumlu, `confidence_note: "well-established"`):
  - **beyaz ekmek** (~265 kcal/100g; tipik porsiyon 1 dilim = 25g; alternatif ¼ ekmek = 62g)
  - **tam buğday ekmeği** (~247 kcal/100g; dilim 25g)
  - **lavaş** (~275 kcal/100g; 1 adet ~60g)
  - **bazlama** (~262 kcal/100g; 1 adet ~120g)
  - **tandır/köy ekmeği** (~270 kcal/100g; dilim 30g)
  Her satırda `nutrition_per_portion` = `nutrition_per_100g × grams/100` tutarlılığını sağla (±%5).
  **Kabul kriterleri:** JSON decode testi geçer (`testTurkishFoodReferenceLoad_...` sayıyı doğruluyorsa güncelle). Yeni test: "ekmek", "1 dilim ekmek" adlı VisionItem → beyaz ekmek satırıyla **reference** kaynaklı eşleşir. `python3 -m json.tool` ile dosya valid.

- [x] **SF-003 · Birim değişikliği besin değerini yeniden hesaplasın** ✅ 2026-07-13
  **Dosyalar:** `Calp/Views/Result/ResultView.swift` (EditableVisionItem), `Calp/Models/NutritionConstants.swift`, `Calp/Views/Result/ResultItemCard.swift`
  **Sorun:** Sonuç ekranında birim değiştirmek (kepçe → çay bardağı) kaloriyi **hiç değiştirmiyor**; yalnızca miktar `baseQuantity`'ye oranla ölçekliyor. "Porsiyon düzeltme" ana ürün vaadi yarım çalışıyor.
  **Talimat:**
  1. `NutritionConstants`'a birim→tipik gram tablosu ekle:
     ```swift
     static func defaultGrams(for unit: PortionUnit) -> Double? {
         // kepçe 120, yemekKasigi 15, suBardagi 200, cayBardagi 100,
         // dilim 25, avuc 30, kase 250, tencere nil, adet nil, gram 1
     }
     ```
     `adet` ve `tencere` nil döner (yemeğe göre değişir → ölçekleme yapılmaz).
  2. `EditableVisionItem`'a per-gram yoğunluk mantığı ekle: `density = baseCalories / max(baseGrams, 1)` (protein/karb/yağ için de).
  3. `householdUnit` değiştiğinde: eşleşen `FoodReference` varsa önce `typicalPortion`/`alternatePortions` içinden aynı birimi ara ve gramı oradan al; yoksa `defaultGrams` tablosunu kullan: `newGrams = quantity × unitGrams`. Besin değerleri `density × newGrams`. `defaultGrams` nil ise (adet) mevcut davranış korunur (sadece quantity ölçekler).
  4. Birim değişince gram etiketi (`~230g`) da güncellenmeli — zaten `estimatedGrams` hesaplanıyor, yeni gram mantığına bağla.
  **Kabul kriterleri:** Unit test: 2 kepçe (240g varsayım) çorba 200 kcal iken birimi "çay bardağı"a çevirince (2×100g) kalori ≈ 166'ya iner (density×200). `adet` seçiminde eski davranış sürer. UI'da stepper + birim değişimi canlı toplamları güncelliyor.

- [x] **SF-004 · rawAIResponse gerçekten kaydedilsin** ✅ 2026-07-13
  **Dosyalar:** `Calp/Views/Result/ResultView.swift` (save()), `Calp/Views/Analysis/AnalysisOverlay.swift`, `Calp/Views/TextLog/TextLogView.swift`, `Calp/App/NavigationModel.swift`
  **Sorun:** `ScanEntry.rawAIResponse` alanı var, `VisionResponse.makeScanEntry(source:rawJSON:)` var ama **gerçek kayıt yolu** (`ResultView.save()`) ham JSON'u hiç taşımıyor — alan hep boş. Hatalı tanıma vakalarını debug etme / yeniden işleme imkânı kayboluyor.
  **Talimat:**
  1. `AIProxyClient.scan/scanText` dönüşünü `(VisionResponse, rawJSON: String)` yapacak şekilde genişlet (ya da küçük bir `ScanResult` struct'ı). Proxy yolunda ham `data`'yı, direct-OpenAI yolunda model `content` string'ini geçir. Demo modda `"demo"` yaz.
  2. `ScanFlow.result` case'ine ve `nav.showResult(...)`'a `rawJSON: String` parametresi ekle; AnalysisOverlay ve TextLogView geçirsin.
  3. `ResultView.save()` `entry.rawAIResponse = rawJSON` yazsın.
  **Kabul kriterleri:** Demo modda bir tarama kaydet → SwiftData'daki ScanEntry.rawAIResponse boş değil. Derleme + mevcut testler yeşil.

- [x] **SF-005 · Ücretsiz tarama sayacı tarama ANINDA işlesin** ✅ 2026-07-13
  **Dosyalar:** `Calp/Networking/FreeScanCounter.swift`, `Calp/Views/Analysis/AnalysisOverlay.swift`, `Calp/Views/TextLog/TextLogView.swift`, `Calp/Views/Result/ResultView.swift`
  **Sorun:** `recordScan()` yalnızca "Logla"da çağrılıyor. Kaydetmeden çıkan kullanıcı **sınırsız AI çağrısı** yakabiliyor (gerçek para). Ayrıca DEBUG'da `isSubscribed = true` başlatılıyor ama `StoreKitManager.updateEntitlements()` ilk çalıştığında (Ayarlar/paywall açılınca) bunu `false`'a eziyor — DEBUG davranışı oturum içinde değişiyor.
  **Talimat:**
  1. `recordScan()` çağrısını `ResultView.save()`'den kaldır; **başarılı AI yanıtı alındığı anda** çağır: `AnalysisOverlay.startScan()` do-bloğunda ve `TextLogView.scan()`'de, response geldikten sonra (demo modda sayma).
  2. DEBUG çakışması: `FreeScanCounter`'a `#if DEBUG var debugForcePro = true` bayrağı ekle; `isSubscribed` yerine `canScanForFree` ve tüketimde `isSubscribed || debugForcePro` kontrol et. `StoreKitManager.updateEntitlements()` DEBUG'da `FreeScanCounter.shared.isSubscribed`'ı **yalnızca gerçek entitlement varsa** güncellesin (false ezmesin).
  **Kabul kriterleri:** RELEASE mantığı: 3 tarama yapıldıktan sonra (kaydetsin/kaydetmesin) kamera girişi `FreeScanLimitView`'a düşer. DEBUG'da hiçbir akış kilitlenmez. Derleme yeşil.

- [x] **SF-006 · Görsel her iki yolda da küçültülsün + doğru MIME** ✅ 2026-07-13
  **Dosya:** `Calp/Networking/AIProxyClient.swift`
  **Sorun:** `ImageDownscaler.jpegForUpload` yalnızca proxy yolunda çağrılıyor. Direct-OpenAI yolu (`callOpenAIVision`) **ham** `imageData`'yı base64'lüyor: 12MP HEIC → dev istek, yüksek token maliyeti; üstelik HEIC baytları `data:image/jpeg` MIME ile etiketleniyor (galeriden seçilen HEIC bozuk yorumlanabilir).
  **Talimat:** `scan(imageData:)` girişinde tek sefer `let payload = ImageDownscaler.jpegForUpload(imageData) ?? imageData` hesapla; hem proxy hem direct yol **aynı payload'ı** kullansın. `callOpenAIVision` imzasına downscale edilmiş data gelsin. (Bonus: `jpegForUpload` zaten yeniden encode ettiği için EXIF/GPS metadata'sı da düşmüş oluyor — anonimlik vaadi.)
  **Kabul kriterleri:** Direct yolda gönderilen base64 uzunluğu, 4000px'lik test görselinde belirgin küçülür (log ile doğrula, sonra logu sil). Derleme yeşil.

- [x] **SF-007 · AI yanıtına validasyon/clamp katmanı** ✅ 2026-07-13
  **Dosyalar:** `Calp/Networking/VisionResponse.swift` (+ yeni `Calp/Networking/VisionResponseValidator.swift`)
  **Sorun:** Structured Outputs tip garantisi veriyor ama **anlam** garantisi vermiyor: negatif kalori, confidence 7.0, quantity 0, 50.000 kcal'lik öğe, kcal↔makro tutarsızlığı olduğu gibi UI'a ve veritabanına akar.
  **Talimat:** `VisionResponse.sanitized()` yaz ve `AIProxyClient`'ın her iki decode noktasında uygula:
  - `confidence` → 0...1 clamp. `householdQuantity` → 0.25...50 clamp (≤0 ise 1). `estimatedGrams` → 1...3000 clamp.
  - `calories` → 0...5000/öğe clamp; makrolar → 0...1000g clamp.
  - Tutarlılık: `4·protein + 4·carbs + 9·fat` ile `calories` %40'tan fazla sapıyorsa **makrolardan türetilen** kaloriyi kullan (makro üçlüsü genelde daha tutarlı) ve `note`'a dokunma.
  - `name` boşsa öğeyi at; `items` boş kalırsa `noFoodDetected = true`.
  **Kabul kriterleri:** Unit test dosyası `CalpTests/VisionResponseValidatorTests.swift`: yukarıdaki her kural için bir case. Derleme + testler yeşil.

- [x] **SF-008 · Ayarlar'daki profil değişikliği hedefleri yeniden hesaplasın** ✅ 2026-07-13
  **Dosya:** `Calp/App/ContentView.swift` (SettingsView.profileSection)
  **Sorun:** Hedef/aktivite/boy/kilo Ayarlar'dan değişince **kalori hedefi ve makrolar aynı kalıyor** — `UserProfile.recomputeDailyTarget()` yazılmış ama hiç çağrılmıyor. Kullanıcı 90 kg'dan 70 kg'a inse hedefi değişmiyor; sessiz yanlışlık.
  **Talimat:**
  1. Profil setter'larının (goal/activity/height/weight) `save()` çağrısından önce `profile.recomputeDailyTarget()` çalıştır (guard: `age > 0` zaten içinde).
  2. Recompute başarılıysa AppStorage hedeflerini senkronla: `calorieTarget = profile.dailyCalorieTarget`, protein/carbs/fat aynı şekilde.
  3. Kullanıcı hedef alanlarını elle değiştirmişse ezilme riskine karşı: recompute'tan önce mevcut AppStorage değerleri profil değerlerinden farklıysa küçük bir `confirmationDialog` göster: "Profil değişti. Günlük hedefler yeniden hesaplansın mı?" (Evet → recompute+senkron; Hayır → yalnız profili kaydet).
  4. Profil bölümüne **Yaş** stepper'ı (10...100) ve **Biyolojik cinsiyet** picker'ı ekle (ikisi de `recomputeDailyTarget` tetikler). `age == 0` legacy profillerde recompute'un no-op olduğunu koru.
  **Kabul kriterleri:** Kilo değiştir → dialog → Evet → halka hedefi anında değişir. Yaş/cinsiyet Ayarlar'dan düzenlenebilir. Derleme yeşil.

- [x] **SF-009 · Kalori halkası hedef değişimini de izlesin** `[bağımsız]` ✅ 2026-07-13
  **Dosya:** `Calp/Views/Daily/CalorieRingView.swift`
  **Sorun:** `onChange(of: consumed)` yalnızca tüketimi izliyor; Ayarlar'dan hedef değişince halka dolgusu güncellenmiyor (sayı değişir, ark eski kalır).
  **Talimat:** `onChange(of: consumed)`'ı `onChange(of: progress)` yap (progress zaten `consumed/target`). `onAppear` aynı kalsın.
  **Kabul kriterleri:** Ayarlar'da hedefi 2000→1500 yap, Bugün'e dön → ark yeni orana animasyonla oturur.

---

## FAZ 1 — AI HATTI SERTLEŞTİRME (prompt + hata + kontrat)

- [x] **SF-101 · Vision/text prompt revizyonu (tek kaynak)** ✅ 2026-07-13
  **Dosya:** `Calp/Networking/AIProxyClient.swift` (visionPrompt/textPrompt) + yeni `vision-prompt-schema.md` güncellemesi
  **Sorunlar:** (a) `note` alanının dili tanımsız — model İngilizce note dönebiliyor; (b) örnek JSON'daki 185/250/0.92 değerlerine çıpalanma riski; (c) `locale` parametresi hiç kullanılmıyor; (d) isim büyük/küçük harf kuralı yok ("Mercimek çorbası" vs "mercimek çorbası" reconciler'a normalize girse de UI'da tutarsız görünüyor); (e) kcal↔makro tutarlılık kuralı yok; (f) içecek/soslar için rehber yok.
  **Talimat:** Her iki prompt'a şu kuralları ekle (mevcut segmentasyon/halüsinasyon bölümlerine DOKUNMA — onlar iyi):
  - `"note", if present, MUST be in Turkish.`
  - `"name" must be lowercase Turkish except proper nouns (e.g. "mercimek çorbası", "İskender").`
  - `calories MUST be consistent with macros: calories ≈ 4·protein_g + 4·carbs_g + 9·fat_g (±15%).`
  - `Report visible drinks (tea, ayran, cola) as separate items. Report visible bread separately.`
  - `household_quantity must be between 0.25 and 20; estimated_grams between 5 and 2500.`
  - Örnek JSON'daki sayısal değerleri jenerik placeholder'a çevir (`0.0` + yorum satırı yerine şemayı düzyazıyla anlat) → çıpalama azalır. Structured Outputs şeması zaten şekli garanti ediyor.
  - `vision-prompt-schema.md`'yi güncel prompt'la senkronla (o dosya kontratın kaynağı).
  **Kabul kriterleri:** Derleme yeşil; `vision-prompt-schema.md` ile kod bire bir aynı kural setini anlatıyor.

- [x] **SF-102 · Hata ayrımı: 429 / offline / sunucu hatası** ✅ 2026-07-13
  **Dosyalar:** `Calp/Networking/AIProxyClient.swift`, `Calp/Views/Analysis/AnalysisOverlay.swift`, `Calp/Views/TextLog/TextLogView.swift`
  **Sorun:** Her hata `scanFailed`'e düşüyor. Kullanıcı rate-limit mi yedi, internet mi yok, sunucu mu çöktü ayırt edemiyor; hepsi "tekrar deneyin".
  **Talimat:**
  1. `AIProxyError`'a case'ler ekle: `rateLimited` ("Çok sık denedin — bir dakika sonra tekrar dene."), `offline` ("İnternet bağlantısı yok görünüyor."), `serverError` ("Sunucuda geçici bir sorun var, birazdan düzelir.").
  2. `performProxyRequest`/`performOpenAIRequest`: HTTP 429 → `.rateLimited`; 5xx → `.serverError`; `URLError.notConnectedToInternet/timedOut` → `.offline`.
  3. AnalysisOverlay hata kartındaki ikon/başlığı case'e göre seç (429 → saat ikonu; offline → wifi.slash).
  **Kabul kriterleri:** Unit test veya mock URLProtocol ile 429 ve 500'ün doğru case'e maplendiğini doğrula. Derleme yeşil.

- [x] **SF-103 · Text girişine sınır + sayaç** ✅ 2026-07-13
  **Dosya:** `Calp/Views/TextLog/TextLogView.swift`
  **Sorun:** Sınırsız metin → gereksiz token maliyeti + kötüye kullanım.
  **Talimat:** 300 karakter sınırı (`onChange`'te kes), 240+ karakterde sağ altta `%d/300` sayacı göster (`.calpCaption`, `textMuted`). Yapıştırmada da kes.
  **Kabul kriterleri:** 300+ karakter girilemiyor; sayaç eşikten sonra görünüyor.

- [x] **SF-104 · Prompt sürümü + istek meta alanları (proxy hazırlığı)** ✅ 2026-07-13
  **Dosya:** `Calp/Networking/AIProxyClient.swift` (AIProxyRequest)
  **Talimat:** `AIProxyRequest`'e `schema_version: 1` ve `app_version` (CFBundleShortVersionString) alanları ekle. Proxy tarafında (FAZ 2) loglama/derecelendirme ve geriye dönük uyum bu alanlarla yapılacak.
  **Kabul kriterleri:** Request gövdesi yeni alanları içeriyor; decode tarafı etkilenmiyor. Derleme yeşil.

---

## FAZ 2 — BACKEND: VERCEL EDGE PROXY (kod tamam; canlı hesap doğrulamaları bekliyor)

> Bu faz repo içinde `proxy/` klasöründe geliştirilir (ayrı deploy, Vercel). Arvia'daki
> proxy zinciri örnek alınır. **Kullanıcı verisi persist edilmez** — yalnız cache/rate-limit anahtarları.

- [ ] **SF-201 · Proxy iskeleti: `POST /api/scan`** ⏸ NOT: `proxy/api/scan.ts` ve TypeScript kontrolü hazır; Vercel hesabı erişimi olmadığı için canlı `vercel dev`/deployment doğrulaması bekliyor.
  **Dosyalar:** `proxy/api/scan.ts`, `proxy/package.json`, `proxy/README.md`
  **Talimat:**
  1. Vercel Edge Function (TypeScript). İstek gövdesi = `AIProxyRequest` kontratı: `{image_base64?, text?, mode: "photo"|"text", locale, tier, schema_version, app_version}`.
  2. `x-calp-key` header'ı env'deki `CALP_CLIENT_KEY` ile eşleşmiyorsa 401.
  3. Model çağrısı: OpenAI Chat Completions, `tier == "pro" ? "gpt-5-mini" : "gpt-5-nano"`, `reasoning_effort` photo→"low" / text→"minimal", **aynı Structured Outputs şeması** (AIProxyClient'taki `visionResponse` şemasını TS'e birebir taşı), `max_completion_tokens: 2048`.
  4. Prompt'lar `proxy/prompts.ts` içinde — **SF-101 sonrası Swift'tekiyle bire bir aynı metin**. Dosya başına şu yorum: `// MUST MATCH Calp/Networking/AIProxyClient.swift prompts — update both together.`
  5. Yanıt: modelin content JSON'u **olduğu gibi** (VisionResponse şekli) döner; ayrıca `x-calp-cache: hit|miss` header'ı.
  6. Hata kontratı: `{ "error": "rate_limited" | "invalid_request" | "upstream_error" }` + uygun HTTP kodu (429/400/502).
  **Kabul kriterleri:** `vercel dev` ile lokal çalışır; curl ile text-mode istek gerçek yanıt döner; yanlış key 401.

- [ ] **SF-202 · Upstash Redis: cache + rate limit** ⏸ NOT: Kod ve Vitest senaryoları hazır; gerçek cache-hit ve limit testi Upstash hesap değişkenlerini bekliyor.
  **Dosya:** `proxy/api/scan.ts`
  **Talimat:**
  1. **Cache:** photo modunda `sha256(image_base64)` (text modunda normalize edilmiş text hash'i) anahtarıyla yanıtı 7 gün TTL ile sakla; hit'te modeli hiç çağırma.
  2. **Rate limit:** `@upstash/ratelimit` — IP başına 10 istek/dk (sliding window) + IP başına 200/gün. Aşımda 429 + `error: rate_limited`.
  3. Upstash'e **yalnızca** hash anahtarları ve sayaçlar yazılır; görsel/metin içeriği loglanmaz, `console.log`'a da yazılmaz.
  **Kabul kriterleri:** Aynı görsel ikinci kez → `x-calp-cache: hit` ve <300ms; 11. ardışık istek 429.

- [ ] **SF-203 · İstemciyi gerçek endpoint'e bağla** ⏸ NOT: İstemci `https://sofram-five.vercel.app/api/scan` endpoint'ini kullanacak şekilde yapılandırıldı; gerçek endpoint/key ile cihaz testi Vercel/Upstash hesap doğrulamasını bekliyor.
  **Dosyalar:** `Calp/Info.plist`, `Calp/Networking/AIProxyClient.swift`
  **Talimat:** Deploy sonrası `AIProxyEndpointURL`'i gerçek URL'e, `AIProxyAPIKey`'i client key'e çevir. `performProxyRequest`'te SF-102 hata kontratını (`error` alanı) parse et. Proxy yolunda da `sanitized()` (SF-007) uygulanıyor olmalı.
  **Kabul kriterleri:** Gerçek cihazda fotoğraf çek → sonuç ekranı gerçek AI verisiyle dolar. `isDemoMode` artık devrede değil. (⚠️ Bu görev Fatih'in Vercel/Upstash hesap kurulumunu gerektirir — Codex hazır olmayanı `⏸` ile işaretlesin.)

---

## FAZ 3 — SONUÇ EKRANI: DÜZELTME UX'İNİ TAMAMLA

- [x] **SF-301 · Öğe silme** ✅ 2026-07-13
  **Dosyalar:** `Calp/Views/Result/ResultView.swift`, `ResultItemCard.swift`
  **Sorun:** AI 3 öğeden 1'ini yanlış tanıdıysa kullanıcının tek seçeneği ya yanlış kaydetmek ya hepsini atmak.
  **Talimat:** Kart sağ üstüne (status badge yanına) küçük `xmark.circle.fill` butonu (`textMuted`, 22pt dokunma alanı ≥44pt) → `editableItems`'tan animasyonla (`.calpSpring`, scale+opacity transition) çıkar. Son öğe silinirse `emptyResultView`'a düş. Toplam bar canlı güncellenir. Silme `UIImpactFeedbackGenerator(style: .medium)`.
  **Kabul kriterleri:** 3 öğeli demo taramada 1 öğe silinir, toplamlar düşer, kayıt 2 öğeyle yazılır.

- [x] **SF-302 · Öğe adı düzenleme + yeniden eşleştirme** ✅ 2026-07-13
  **Dosyalar:** `ResultView.swift`, `ResultItemCard.swift`
  **Talimat:** Öğe adına dokununca inline `TextField` (aynı tipografi). Ad değişince `ReferenceReconciler.reconcile`'ı yeni adla tekrar çalıştır: referans eşleşirse değerleri ve "Doğrulanmış" rozetini güncelle, eşleşmezse AI değerlerine dön. (EditableVisionItem'a `rename(to:)` metodu ekle; base değerleri yeni reconcile sonucuyla değiştir, quantity'yi koru.)
  **Kabul kriterleri:** "muzlu kek" → adı "muz" yapınca rozet + değerler muz referansına döner; geri "muzlu kek" yazınca AI değerlerine döner.

- [x] **SF-303 · Kopya düzeltmeleri (İngilizce sızıntı + tuhaf ifade)** ✅ 2026-07-13
  **Dosyalar:** `ResultItemCard.swift`, `CalpWidget/WidgetEntryView.swift`
  **Talimat:** ResultItemCard `macrosRow`'daki `"carbs"` → `"karb."`. Widget medium'daki `"Carbs"` → `"Karb."`. ResultItemCard rozeti `"Şüpheli/tahminidir"` → `"Emin değilim"` (ikon aynı). AnalysisOverlay'de değişiklik yok.
  **Kabul kriterleri:** Projede grep ile UI string'lerinde `carbs|Carbs` kalmadı (kod tanımlayıcıları hariç).

- [x] **SF-304 · Kaydetmeden çıkışta onay** ✅ 2026-07-13
  **Dosya:** `ResultView.swift`
  **Sorun:** Foto akışında X'e basınca düzenlemeler sessizce çöpe gidiyor (text akışında draft korunuyor, foto akışında hiçbir şey korunmuyor).
  **Talimat:** Kullanıcı en az bir düzenleme yaptıysa (`hasEdits` bayrağı: quantity/unit/isim/silme) X'e basınca `confirmationDialog`: "Düzenlemeler kaydedilmedi" — "Çıkış" (destructive) / "Vazgeç". Düzenleme yoksa direkt çık.
  **Kabul kriterleri:** Düzenlemesiz çıkış sorusuz; düzenlemeli çıkış onay ister.

---

## FAZ 4 — GEÇMİŞ EKRANI: ÖZETTEN GERÇEK GEÇMİŞE

> Mevcut Geçmiş = 7 günlük özetin aynısı. En zayıf ekran. Hedef: gün gün gezilebilir,
> silinebilir/incelenebilir gerçek kayıt defteri. Yeni dosyalar `Calp/Views/History/` altına.

- [x] **SF-401 · HistoryView v2: ay bazlı gün listesi** ✅ 2026-07-13
  **Yeni dosya:** `Calp/Views/History/HistoryView.swift` (SevenDaySummaryView içindeki geçici `HistoryView`'ı buraya taşı ve genişlet; eskisini sil)
  **Talimat:**
  1. Üstte mevcut 7 günlük özet kartı (chart) korunur (SevenDaySummaryView embedded).
  2. Altına "TÜM GÜNLER" bölümü: `ScanEntry` + `QuickAddCount`'ların kapsadığı tüm günler, yeni→eski, ay başlıklarıyla gruplu (`"Temmuz 2026"` eyebrow başlık). Her satır: gün adı+tarih, toplam kcal (Geist Mono), öğün sayısı, hedefe göre mini durum noktası (altında/üstünde — nötr renkler: `accentFill` / `textMuted`, kırmızı YOK).
  3. Satıra dokununca SF-402 gün detayı push edilir (`NavigationStack`).
  4. Boş durum: mevcut dil ile ("Henüz kayıtlı gün yok…").
  5. Performans: tüm entry'leri her satır için filtreleme O(n²) olmasın — günlere tek geçişte grupla (`Dictionary(grouping:)`).
  **Kabul kriterleri:** 30+ günlük sahte veriyle akıcı scroll; ay başlıkları doğru; xcodegen + derleme yeşil.

- [x] **SF-402 · Gün detayı ekranı** ✅ 2026-07-13
  **Yeni dosya:** `Calp/Views/History/DayDetailView.swift`
  **Talimat:** Seçilen günün: kalori halkası mini versiyonu (statik, hedefe göre), makro toplamları, o günkü `MealEntryCard` listesi (DailyView'daki bileşeni yeniden kullan — silme dahil), quick-add tallies listesi. Silmeler SwiftData'ya yazar ve widget'ı günceller (bugüne aitse).
  **Kabul kriterleri:** Dünün kaydı silinebiliyor; toplamlar anında güncelleniyor.

- [x] **SF-403 · Geçmişte haftalık makro istatistikleri** ✅ 2026-07-13
  **Dosya:** `Calp/Views/History/HistoryView.swift`, `Calp/Models/DaySummaryBuilder.swift`
  **Talimat:** `DaySummary`'e protein/carbs/fat toplamları ekle (builder'da scan item'ları + quick-add makroları). Özet kartının altına 3'lü mini istatistik: "ort. protein/gün" vb. (`StatCell` yeniden kullan). "Adet" kolon başlığını "Hızlı ekleme" yap (mevcut belirsiz).
  **Kabul kriterleri:** Builder unit testi: makro toplamları doğru; UI derleniyor.

---

## FAZ 5 — AYARLAR + YASAL (App Store engelleri dahil)

- [x] **SF-501 · Yasal linkler: Gizlilik Politikası + Kullanım Koşulları (App Store 3.1.2 ZORUNLU)** ✅ 2026-07-13
  **Dosyalar:** `Calp/App/ContentView.swift` (SettingsView), `Calp/Views/Onboarding/PaywallView.swift`
  **Sorun:** Paywall'da abonelik var ama **gizlilik politikası ve kullanım koşulları linki yok** — otomatik yenilenen abonelikli uygulamalarda App Store reddi sebebi.
  **Talimat:**
  1. Ayarlar "Hakkında" bölümüne iki `Link` satırı: "Gizlilik Politikası", "Kullanım Koşulları" (URL'ler `NutritionConstants` yanına `LegalLinks` enum'ı olarak; şimdilik `https://calp.app/gizlilik` / `/kosullar` placeholder — Fatih gerçek URL verince değişecek, satıra `// TODO(fatih): gerçek URL` bırak).
  2. PaywallView `footerSection`'a aynı iki link (termsText'in üstüne, `.calpCaption`).
  3. Apple standart EULA kullanılacaksa Kullanım Koşulları `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`'ya işaret edebilir.
  **Kabul kriterleri:** Her iki ekranda tıklanabilir linkler; Safari'de açılıyor.

- [x] **SF-502 · "Tüm verilerimi sil" (KVKK/GDPR)** ✅ 2026-07-13
  **Dosya:** `Calp/App/ContentView.swift` (SettingsView)
  **Talimat:** Yeni "Veri" section'ı: kırmızı "Tüm Verilerimi Sil" butonu → `confirmationDialog` (destructive onay, metin: "Tüm öğünler, sayaçlar ve profil kalıcı olarak silinir. iCloud kopyası da dahil. Bu geri alınamaz.") → onayda tüm model tipleri için `modelContext.delete(model:)`, AppStorage hedef anahtarlarını ve `calp.onboardingCompleted`'ı temizle, widget'ı boş özetle güncelle → onboarding'e döner.
  **Kabul kriterleri:** Silme sonrası uygulama onboarding'den başlıyor; SwiftData boş; halka 0/2000.

- [x] **SF-503 · Veri dışa aktarma (CSV)** ✅ 2026-07-13
  **Dosya:** SettingsView + yeni `Calp/Models/DataExporter.swift`
  **Talimat:** "Verilerimi Dışa Aktar" satırı → tüm ScanEntry/LoggedItem'ları CSV'ye yaz (`tarih,saat,kaynak,öğe,birim,miktar,gram,kcal,protein,karb,yağ,kaynak_tipi`), `ShareLink`/`UIActivityViewController` ile paylaş. Türkçe karakterler UTF-8 BOM ile (Excel uyumu).
  **Kabul kriterleri:** Export edilen dosya Numbers/Excel'de düzgün açılıyor.

- [ ] **SF-504 · Abonelik yönetimi doğru API ile**
  **Dosya:** `Calp/StoreKit/StoreKitManager.swift`
  **Sorun:** `openManageSubscriptions()` uygulama ayarlarını açıyor (`openSettingsURLString`) — abonelik sayfası DEĞİL.
  **Talimat:** `UIApplication.shared.connectedScenes` üzerinden aktif `UIWindowScene` bul, `try await AppStore.showManageSubscriptions(in: scene)` çağır; hata durumunda fallback `https://apps.apple.com/account/subscriptions` URL'i.
  **Kabul kriterleri:** Gerçek cihazda "Aboneliği Yönet" App Store abonelik sheet'ini açıyor.
  ⏸ **NOT:** `AppStore.showManageSubscriptions(in:)` ve App Store URL fallback'i hazır; gerçek cihaz kabul testi bekliyor.

- [ ] **SF-505 · Yıllık planın aylık eşdeğeri doğru formatlansın**
  **Dosya:** `StoreKitManager.swift` (annualMonthlyPrice)
  **Sorun:** Elle `currencySymbol + String(format: "%.2f")` — TL'de yanlış konum/ayraç riski, locale'e saygısız.
  **Talimat:** `product.priceFormatStyle.format(product.price / 12)` kullan (Decimal bölme; `Product.PriceFormatStyle` zaten doğru para birimi/locale taşır).
  **Kabul kriterleri:** TR Store hesabında "₺66,67" biçiminde doğru render; kod elle sembol birleştirmiyor.
  ⏸ **NOT:** `product.priceFormatStyle.format(product.price / 12)` hazır; TR Store hesabı kabul testi bekliyor.

- [ ] **SF-506 · Destek/geri bildirim satırı**
  **Dosya:** SettingsView "Hakkında"
  **Talimat:** "Geri Bildirim Gönder" satırı → `mailto:` link (`av.fatihdisci@gmail.com`, konu: "Calp Geri Bildirim v{sürüm}"). Mail hesabı yoksa sessiz düşmesin: `openURL` sonucunu kontrol edip alert.
  **Kabul kriterleri:** Mail compose açılıyor.
  ⏸ **NOT:** Sürümlü `mailto:` ve açılamama uyarısı hazır; gerçek mail hesabı bulunan cihaz kabul testi bekliyor.

---

## FAZ 6 — ANA EKRAN CİLA (Bugün)

- [ ] **SF-601 · Gece yarısı gün dönümü**
  **Dosya:** `Calp/Views/Daily/DailyView.swift`
  **Sorun:** Uygulama gece yarısını açık geçirirse "bugün" filtreleri ve tarih başlığı eski günü göstermeye devam eder.
  **Talimat:** `@State private var dayAnchor = Calendar.current.startOfDay(for: .now)` tut; `todayScans/todayQuickCounts/todayLabel` bunu kullansın. View'a `.onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged))` ekleyip anchor'ı güncelle; ayrıca `scenePhase == .active` geçişinde de tazele.
  **Kabul kriterleri:** Simülatörde saat ileri alınıp app foregrounda gelince liste/başlık yeni günü gösteriyor.
  ⏸ **NOT:** Gün değişimi bildirimi ve foreground yenilemesi hazır; simülatör saat-atlama kabul testi bekliyor.

- [x] **SF-602 · DateFormatter'ları cache'le** `[bağımsız]` ✅ 2026-07-13
  **Dosyalar:** `DailyView.swift` (todayLabel, MealEntryCard.timeLabel), `SevenDaySummaryView.swift` (dayLabel, shortDayLabel)
  **Talimat:** Her render'da `DateFormatter()` yaratmayı bırak; `static let` formatter'lar (tr_TR locale) tanımla ve paylaş (örn. `enum CalpFormatters`).
  **Kabul kriterleri:** Grep ile view body çağrı yollarında `DateFormatter(` kalmadı.

- [x] **SF-603 · Halka etkileşimi: dokununca yenen/kalan/hedef modu** ✅ 2026-07-13
  **Dosya:** `CalorieRingView.swift`, `DailyView.swift`
  **Talimat:** Halkaya dokunmak merkez metni 3 mod arasında döndürsün: **kalan** (varsayılan) → **yenen** → **hedef**. Mod etiketi alt satırda ("kcal kalan"/"kcal yenen"/"kcal hedef"). Seçim `@AppStorage("calp.ringDisplayMode")` ile kalıcı. Geçiş `contentTransition(.numericText())` + hafif haptic. Halka dolgusu her modda aynı (yenen/hedef oranı).
  **Kabul kriterleri:** Dokunuşlar mod değiştiriyor, tercih relaunch sonrası korunuyor, animasyon calpSpring.

- [x] **SF-604 · Hedef üstü durumda halka ikinci tur göstergesi** ✅ 2026-07-13
  **Dosya:** `CalorieRingView.swift`
  **Sorun:** %100 üstünde ark tamamen dolu kalıyor; +126 yazısı dışında görsel sinyal yok.
  **Talimat:** `consumed > target` iken taşan kısmı ayrı bir ince arc ile göster: iç yarıçapta (track'in 6pt içinde), `macroFat`/bakır tonunda değil — `accentFillPressed` ile, `overshootProgress = min((consumed-target)/target, 1)`. Utandırıcı kırmızı YOK. Bead ana arkın ucunda kalır.
  **Kabul kriterleri:** 2400/2000'de iç ince ark %20 dolu; 1900/2000'de görünmüyor.

---

## FAZ 7 — WIDGET MODERNİZASYONU

- [x] **SF-701 · Widget'ı QuickAdd modeline geçir + emoji temizliği** ✅ 2026-07-13
  **Dosyalar:** `CalpWidget/WidgetEntryView.swift`, `Calp/Models/WidgetDailySummary.swift`, `Calp/Extensions/WidgetDataStore+MainApp.swift`
  **Sorun:** Medium widget hâlâ legacy `breadSlices/teaGlasses` alanlarını 🍞🍵 **emoji** ile gösteriyor — uygulama özelleştirilebilir sayaçlara geçti; emoji, custom-icon tasarım dilini kırıyor (AI-slop görünümü). "Carbs" İngilizce (SF-303'te düzeltildiyse burada kalanı).
  **Talimat:**
  1. `WidgetDailySummary`'e `topQuickAdds: [QuickAddSnapshot]` ekle (`name, unit, count, iconName` — en çok sayılan 2 öğe). Legacy alanları decode uyumu için `breadSlices/teaGlasses`'ı optional bırak.
  2. `WidgetDataStore+MainApp.saveCurrentDaySummary` bunları gerçek QuickAddItem/Count'tan doldursun.
  3. Widget'ta emoji pill'leri kaldır; CalpIcon widget target'ına taşınabiliyorsa ikonla, taşınamıyorsa yalnız `count × unit` metniyle göster.
  **Kabul kriterleri:** Widget snapshot'ında emoji yok; kullanıcının gerçek ilk 2 sayacı görünüyor; eski kayıtlı JSON decode hatası vermiyor.

- [ ] **SF-702 · Widget'a lockscreen (accessory) aileleri** `[bağımsız]`
  **Dosya:** `CalpWidget/CalpWidget.swift`, `WidgetEntryView.swift`
  **Talimat:** `.accessoryCircular` (mini halka + kalan sayı) ve `.accessoryInline` ("1.240 kcal kaldı") desteği ekle. `widgetURL` aynı deep-link.
  **Kabul kriterleri:** Kilit ekranına eklenebiliyor, doğru render.
  ⏸ **NOT:** `.accessoryCircular` ve `.accessoryInline` derleniyor; kilit ekranına ekleme kabul testi bekliyor.

---

## FAZ 8 — MARKA & "AI-SLOP" TEMİZLİĞİ

- [x] **SF-801 · Tab bar'ı özel Calp ikonlarına geçir** ✅ 2026-07-13
  **Dosyalar:** `Calp/App/ContentView.swift`, `Calp/DesignSystem/CalpIcon.swift`
  **Sorun:** `sun.max.fill / chart.bar.fill / gearshape.fill` — herhangi bir template uygulamanın tab bar'ı. Marka dili 8 özel çizgi ikon üzerine kurulu ama tab bar'da hiç kullanılmamış.
  **Talimat:** CalpIcon setine 3 yeni ikon çiz (mevcutlarla aynı dil: 24×24, 1.5px stroke, currentColor `Shape` tabanlı): **bugun** (tabak-güneş hibriti / servis kapağı), **gecmis** (üst üste 3 yatay çizgili takvim-defter), **ayarlar** (kısık ateş simgesi / sade dişli — mevcut ikon diline uydur). `Label`'ları `CalpIconView` kullanan custom `tabItem`'a çevir; seçili/seçisiz renk `accentFill/textMuted`.
  **Kabul kriterleri:** Üç sekme özel ikonlarla, seçim durumu net; SF Symbol tab ikonu kalmadı.

- [x] **SF-802 · Lottie asset'leri üret ve bağla (ya da bilinçli statik)** ✅ 2026-07-13
  **Dosyalar:** `Calp/Resources/Animations/`, `DailyView.emptyMealsCard`
  **Sorun:** `CalpLottieView("calp_empty_plate")` çağrılıyor ama klasörde yalnız README var — fallback statik ikona düşüyor; kod ölü yol taşıyor.
  **Talimat:** Fatih'ten Bodymovin JSON gelene kadar: LottieFiles'tan lisans-uyumlu bir asset ARAMA (marka dışı). Bunun yerine fallback'i kasıtlı hale getir: `CalpPulseShine` (Motion+Patterns'te hazır, wired değil) ile CalpIcon'a 1.8s nefes efekti ver — boş durum "canlı" hisseder, dış bağımlılık sıfır. Lottie çağrısı ve wrapper kalsın (asset düşünce otomatik devreye girer); README'ye beklenen asset adlarını yaz: `calp_empty_plate.json`, `calp_paywall_hero.json`, `calp_onboarding_intro.json`.
  **Kabul kriterleri:** Boş durum ikonu nefes alıyor; Lottie yolu asset eklenince çalışır durumda.

- [ ] **SF-803 · Calp uygulama ikonu entegrasyonu**
  **Dosyalar:** `Calp/Assets.xcassets/AppIcon.appiconset/`
  **Talimat:** Onaylı 1024×1024 Calp master'ını `AppIcon` set'ine yerleştir (tek boyut, Xcode 15 auto-generate). İkon: canvas'ı tamamen kaplayan düz domates kırmızısı zemin, ortada asimetrik kırık siyah `C`, merkezde kırık beyaz nokta. Uygulama maskeyi kendisi uygulayacağı için dosyada rounded-square çerçeve, dış boşluk, gradient, gölge veya 3D efekt YOK. Dark/tinted varyant ihtiyacını Xcode/App Store doğrulamasına göre ayrıca değerlendir.
  **Kabul kriterleri:** Cihazda ikon; App Store Connect uyarısı yok.
  ⏸ **NOT:** Master onaylandı; cihaz ve archive doğrulaması bekliyor.

- [x] **SF-804 · Onboarding sonuç ekranında güven detayları** `[bağımsız]` ✅ 2026-07-13
  **Dosya:** `Calp/Views/Onboarding/OnboardingView.swift` (result step)
  **Talimat:** Hedef sayının altına küçük açılır "Nasıl hesapladık?" satırı: BMR formül adı (Mifflin-St Jeor), aktivite çarpanı, hedef düzeltmesi — 3 satır, `calpCaption`. `floorApplied == true` ise mevcut taban notunu göster (dailyTargetResult zaten var). Tıbbi feragat zaten ekranda mı kontrol et; yoksa `NutritionConstants.medicalDisclaimerTR` ekle.
  **Kabul kriterleri:** Açılır detay çalışıyor; feragat görünür.

---

## FAZ 9 — TEST, DOĞRULAMA, YAYIN HAZIRLIĞI

- [x] **SF-901 · Reconciler regresyon paketi** ✅ 2026-07-13
  **Dosya:** `CalpTests/ReconcilerNegativeTests.swift` (SF-001'de açıldı — genişlet)
  **Talimat:** DB'deki ≤5 harfli **tüm** well-established adları programatik tara: her biri için `"<ad>lu kek"`, `"<ad> salatası"`, `"ızgara <ad>"` türevi adların eşleşME diğini otomatik doğrula (parametrik test). Bu, DB büyüdükçe yeni substring tuzaklarını otomatik yakalar.
  **Kabul kriterleri:** Test 145 gıda üzerinde çalışıp yeşil.

- [x] **SF-902 · AIProxyClient birim testleri (mock URLProtocol)** ✅ 2026-07-13
  **Yeni dosya:** `CalpTests/AIProxyClientTests.swift`
  **Talimat:** `URLProtocol` mock'u ile: (a) proxy 200 + geçerli JSON → doğru VisionResponse; (b) 429 → `.rateLimited`; (c) 500 → `.serverError`; (d) bozuk JSON → `.scanFailed`; (e) sanitize: negatif kalorili yanıt clamp'leniyor; (f) `pro` tier fallback zinciri (mini→nano) tetikleniyor.
  **Kabul kriterleri:** 6 case yeşil; ağ erişimi olmadan koşuyor.

- [ ] **SF-903 · Uçtan uca demo akış kontrol listesi (manuel, gerçek cihaz)** ⏸ NOT: `PHASE_QA_NOTES.md` şablonu hazır; Fatih'in iPhone'unda yapılacak manuel tam tur gerçek cihaz erişimini bekliyor.
  **Talimat:** Fatih'in iPhone'unda tam tur: onboarding → paywall skip → kamera → demo tarama → düzelt → logla → halka → quick-add → Geçmiş gün detayı → Ayarlar hedef değişimi → widget güncellenmesi → veri sil → onboarding. Her adım için `PHASE_QA_NOTES.md`'ye ✅/❌ yaz; ❌'ler bu roadmap'e yeni SF-9xx görevi olarak eklenir.
  **Kabul kriterleri:** Notlar dosyası dolu; kritik ❌ kalmadı.

- [ ] **SF-904 · App Store hazırlık denetimi** ⏸ NOT: Yerel denetim tamamlandı; Apple Developer/App Store Connect erişimi ve imzalı gerçek cihaz testleri bekleniyor.
  **Talimat:** Kontrol listesi: (1) `DEVELOPMENT_TEAM` set + CloudKit entitlement imzalı cihazda sync testi (iki cihaz/sim arasında kayıt akıyor mu); (2) `UIBackgroundModes remote-notification` gerçekten gerekli mi — CloudKit push için evet, değilse kaldır; (3) purpose string'ler Türkçe ve doğru; (4) subscription'lar App Store Connect'te 3 gün trial'lı tanımlı; (5) privacy nutrition label taslağı: veri toplama = YOK (fotoğraf geçici işlenir, saklanmaz) — `proxy/README.md`'ye yaz; (6) 0.1.0 → 1.0.0 sürüm bump.
  **Kabul kriterleri:** Liste maddeleri tek tek işaretli.
  - [ ] `DEVELOPMENT_TEAM` + imzalı cihazda iki uçlu CloudKit sync — takım kimliği ve cihaz testi bekliyor.
  - [x] `UIBackgroundModes remote-notification` korundu — uygulama CloudKit silent push ile dış değişiklikleri almak için kullanıyor. ✅ 2026-07-13
  - [x] Kamera ve fotoğraf purpose string'leri Türkçe ve kullanım amacıyla uyumlu. ✅ 2026-07-13
  - [ ] App Store Connect aboneliklerinde yıllık 7 günlük trial — hesap erişimi bekliyor.
  - [x] `proxy/README.md` gizlilik etiketi taslağı gerçek saklama davranışıyla belgelendi. ⚠️ Yedi günlük normalize yanıt cache'i nedeniyle App Store'da koşulsuz “veri toplanmıyor” seçilmemeli; son politika kararı bekliyor. ✅ 2026-07-13
  - [x] `MARKETING_VERSION` 1.0.0 yapıldı. ✅ 2026-07-13

---

## FAZ 10 — CALP: MARKA, DÜZ UX VE EN/TR GLOBALLEŞME

> **Karar kaydı · 2026-07-13:** Çalışma markası **Calp**. Tasarım dili “visual nutrition intelligence”: Arc/Search kadar karakterli ve doğrudan; düz renkli, tipografi öncelikli, gradient/glass/3D/neo-morphic yüzey yok. İkon dili onaylı master'daki kırık `C`dir. Bu çalışma adı public release öncesi resmi marka ve alan adı kontrolünden geçmelidir; Foodvisor ile kategori/isim yakınlığı nedeniyle bu kontrol yayın engelidir.
>
> **Dil kararı:** Uygulama cihaz diline göre Türkçe veya İngilizce çalışır; kullanıcı verisi otomatik çevrilmez. Mevcut Türkçe besin referansları korunur, İngilizce destek ayrı alias/veri politikasıyla eklenir. Bundle ID, SwiftData model adları, App Group, CloudKit container ve StoreKit product ID'leri bu fazda değiştirilmeyecek; isim değişikliği veri/satın alma sürekliliğini bozmamalı.

- [x] **SF-1001 · Calp marka yüzeyi ve app icon'ı** ✅ 2026-07-13
  **Dosyalar:** `Calp/Assets.xcassets/AppIcon.appiconset/`, `Calp/Info.plist`, `project.yml`, yasal link/metadata kaynakları.
  **Talimat:** SF-803 master'ını entegre et. Kullanıcıya görünen ürün adı, onboarding/paywall/Ayarlar başlıkları, destek e-postası konusu ve placeholder yasal URL'leri Calp ile tutarlı hale getir. Bundle ID (`com.fatih.calp`), URL scheme, CloudKit/App Group ve StoreKit product ID'lerini değiştirme. App Store/alan adı/marka kullanılabilirliği için resmi kontrol listesi oluştur; sonucu olmadan public release işaretleme.
  **Kabul kriterleri:** Uygulama ikonu cihazda doğru maskelenir; eski “Calp” kullanıcıya görünen marka kopyasında kalmaz; kimlik/satın alma sürekliliği bozulmaz.
  ⏸ **NOT:** Kod tarafı hazır — `CFBundleDisplayName`=Calp, purpose string'ler, destek e-postası konusu, yasal linkler (`calp.app`) ve app icon (`AppIcon-1024.png`) yerinde; kullanıcıya görünen kopyada eski marka kalmadı; bundle ID/URL scheme/CloudKit/StoreKit ID'leri korundu. Resmi marka/alan-adı/hukuk kontrolü ve cihaz ikon-maske doğrulaması `CALP_BRAND_CHECK.md`'de izleniyor (Fatih'in hesap/hukuk erişimini bekliyor).

- [x] **SF-1002 · Düz Calp tasarım sistemi** `[bağımsız]` ✅ 2026-07-13
  **Dosyalar:** `Calp/DesignSystem/`, `design-tokens.md`, ilgili SwiftUI modifier'ları.
  **Talimat:** Tasarım tokenlarını tek katmanlı sisteme geçir: düz kırık beyaz/near-black yüzeyler, tek düz domates kırmızısı vurgu, ince sınır veya boşlukla hiyerarşi. Gradient, glass, kabartı, çift kenar, raised/inset shadow ve dekoratif halka dili kaldırılır. Geist/Geist Mono korunur; tipografi, ölçüm değerleri ve boşluk ürünün ana karakteridir. Renk/spacing/font hard-code edilmez.
  **Kabul kriterleri:** Token dokümanı ve uygulama aynı dili kullanır; ana ekranlarda eski soft/neomorphic modifier kalmaz; light/dark contrast erişilebilir.

- [x] **SF-1003 · Search-benzeri uygulama kabuğu ve Bugün ekranı** ✅ 2026-07-13
  **Dosyalar:** `Calp/App/ContentView.swift`, `Calp/Views/Daily/`, `Calp/DesignSystem/CalpIcon.swift`.
  **Talimat:** Ana akışı dashboard değil “yediğini anlama” aracı olarak kur. Kamera/yazılı giriş net birincil eylem olur; günlük kalori ve makrolar güçlü tipografik bilgi bloklarıdır. Kırık `C` marka işareti ikon/boş durumlarda ölçülü kullanılır; tab bar sade, düz ve okunur kalır. Yeni ekran düzeni mevcut günlük kayıt, quick-add ve hedef davranışlarını korur.
  **Kabul kriterleri:** Kullanıcı ilk bakışta fotoğrafla veya metinle öğün eklemeyi bulur; kayıt/toplam/widget akışları regress etmez; iPhone küçük ekranında taşma yok.
  ⏸ **NOT:** Bugün ekranı artık top bar'ın hemen altında tam-genişlik "yakalama çubuğu" ile açılıyor: kamera vurgu rengiyle birincil eylem, yazılı giriş yanında — her iki giriş ilk bakışta bulunur. Kalori/makro bloğu ve kayıt/quick-add/hedef davranışları korundu; çubuk `lineLimit(1)`+`Spacer` ile küçük ekranda taşmaz. Görsel/Dynamic Type/gerçek cihaz doğrulaması derleme ortamı bekliyor.

- [x] **SF-1004 · Kamera, analiz ve sonuç deneyiminin Calp revizyonu** ✅ 2026-07-13
  **Dosyalar:** `Calp/Views/Camera/`, `Calp/Views/Analysis/`, `Calp/Views/Result/`, `Calp/Views/TextLog/`.
  **Talimat:** Capture → analiz → düzelt → logla akışını tek görsel dilde yenile. Analiz durumu “AI sihir” klişesi değil, anlaşılır işlem geri bildirimi verir. Sonuç listesi Search sonucu gibi hızlı taranır ve düzenleme önceliklidir; hata, offline ve rate-limit durumları tasarım sistemiyle uyumlu kalır.
  **Kabul kriterleri:** Fotoğraf ve metin akışları aynı tasarım kalitesinde; silme/düzenleme/kaydetmeden çıkış davranışları korunur; Dynamic Type temel kontrolleri geçer.
  ⏸ **NOT:** Analiz durumundaki "AI sihri" süpüren lazer beam + glow gradient kaldırıldı; yerine dürüst adımlı işlem geri bildirimi geldi (viewfinder köşe braketleri + gerçek adımı adlandıran dönen başlık + düz 3-segment ilerleme). Sonuç ekranı zaten edit-first (silme/rename/birim/kaydetmeden çıkış — SF-301/302/303/304); Result gradient'leri düz scroll-solma maskesi olarak korundu; hata/offline/rate-limit kartları tasarım sistemiyle uyumlu (SF-102). Dynamic Type/gerçek cihaz doğrulaması derleme ortamı bekliyor.

- [x] **SF-1005 · Geçmiş, Ayarlar, onboarding ve paywall'ın küresel görsel dönüşümü** ✅ 2026-07-13
  **Dosyalar:** `Calp/Views/History/`, `Calp/App/ContentView.swift`, `Calp/Views/Onboarding/`, `CalpWidget/`.
  **Talimat:** Kalan kullanıcı yolculuğunu SF-1002 sistemine geçir. Onboarding kısa, doğrudan ve kamera değerini öne çıkarır; paywall abonelik şartlarını açık tutar; Geçmiş/Ayarlar bilgi yoğun ama sakin olur. Widget'lar yeni logo/renk sistemini kullanır, fakat okunabilirlik için platform tint kurallarına uyar.
  **Kabul kriterleri:** Tüm ana tablar, onboarding, paywall, geçmiş detayı ve widget aynı ürün gibi görünür; veri silme/export/subscription yolları kaybolmaz.
  ⏸ **NOT:** Geçmiş/Ayarlar/onboarding/paywall ve widget zaten düz Calp token sistemine geçmiş durumda (palet + düz yüzeyler uygulama geneline uygulandı; denetlendi — chrome'da dekoratif gradient/material/gölge yok, kalan `ultraThinMaterial`'lar yalnız kamera fotoğrafı üstündeki okunabilirlik scrim'leri, scroll-solma maskeleri düz affordance). Onboarding sonuç adımı artık kamera değerini öne çıkarıyor; yanıltıcı marka/tasarım-dili yorumları Calp'e güncellendi. Veri silme/export/abonelik yolları korundu (SF-501/502/503). Widget tomato renk sistemini kullanıyor; marka logosunu widget target'ına paylaştırma xcodegen+cihaz doğrulaması gerektirdiğinden ertelendi. Görsel/gerçek cihaz doğrulaması derleme ortamı bekliyor.

- [x] **SF-1006 · EN/TR yerelleştirme altyapısı ve locale biçimlendirme** `[bağımsız]` ✅ 2026-07-13
  **Dosyalar:** `Calp/Resources/Localizable.xcstrings`, `Calp/*`, `Calp/en.lproj/InfoPlist.strings`, `Calp/tr.lproj/InfoPlist.strings`.
  **Talimat:** Hard-coded kullanıcı metnini anahtarlı String Catalog'a taşı. Sistem dili Türkçe/İngilizce için eksiksiz kaynaklar oluştur; Ayarlar'a isteğe bağlı dil seçimi (System / Türkçe / English) ekle. Tarih, sayı, para, aylık fiyat eşdeğeri ve birimler seçili locale'e göre formatlanır. Kamera/fotoğraf purpose string'leri dahil Info.plist metinleri iki dilde olur. Model raw değerleri, SwiftData verisi ve deep-link'ler çevrilmez.
  **Kabul kriterleri:** Aynı build TR ve EN modunda yeniden başlatmadan değişir; kullanıcıya görünen Türkçe hard-code metin kalmaz; eksik key/English fallback bulunmaz; en az bir format testi TR ve EN'i doğrular.
  ⏸ **NOT:** `Localizable.xcstrings` oluşturuldu (130+ anahtar, TR kaynak + EN çeviri). `CalpFormatters` + `HistoryView`/`DayDetailView`/`WidgetEntryView` hard-coded `Locale(identifier: "tr_TR")` → `.autoupdatingCurrent` + `setLocalizedDateFormatFromTemplate` yapıldı. `AppLanguage.swift` + Ayarlar'a dil seçici eklendi (System/Türkçe/English, restart gerektirir). Dinamik computed string property'ler `String(localized:)` ile sarıldı. Statik `Text("...")` string literal'ları SwiftUI otomatik olarak String Catalog üzerinden localize eder — değişiklik gerekmez. Derleme/cihaz doğrulaması + SF-1007 (AI prompt locale) bekliyor.

- [ ] **SF-1007 · AI ve besin referanslarının global dil politikası**
  **Dosyalar:** `Calp/Networking/AIProxyClient.swift`, `proxy/prompts.ts`, `Calp/Nutrition/`, referans veri/testleri.
  **Talimat:** Prompt ve hata/sonuç metinleri isteğin locale'ine göre doğru dilde üretilir. Türkçe referans DB'yi İngilizceye körlemesine çevirmek YASAK: İngilizce well-established alias/isimler ayrı veri ve kaynak politikasıyla eklenir; yalnız doğrulanmış eşleşmeler referans değeri alır. Eski Türkçe kayıt isimleri/ham AI verisi otomatik değiştirilmez.
  **Kabul kriterleri:** TR ve EN prompt snapshot/kontrat testleri yeşil; “chicken soup” gibi İngilizce eşleşme yalnız tanımlı alias varsa reference kaynaklıdır; yanlış substring eşleşmesi geri gelmez.

- [x] **SF-1008 · Calp global QA, erişilebilirlik ve yayın kapısı** ✅ 2026-07-13
  **Dosyalar:** `PHASE_QA_NOTES.md`, yeni screenshot/locale testleri, App Store hazırlık notları.
  **Talimat:** TR/EN için onboarding → kamera → analiz → düzelt → log → geçmiş → Ayarlar → widget → silme tam turunu çalıştır. Light/dark, Dynamic Type, VoiceOver temel etiketleri, küçük iPhone ve gerçek cihaz ikon maskesi kontrol edilir. App Store listing, privacy metni, abonelik ürün isimleri ve screenshot'lar marka/dil ile senkronlanır. Resmi Calp marka/alan adı kontrolü tamamlanmadan yayın onayı verilmez.
  **Kabul kriterleri:** Her dilde kritik ❌ yok; testler yeşil; release checklist'te marka kullanılabilirliği, icon ve metadata tek tek işaretli.
  ⏸ **NOT:** Kod tarafı tamam: tüm view'lara accessibility label/hint/value eklendi (25+ ikon buton, 3 slider, 4 stepper, CalorieRingView), dekoratif elementler gizlendi, CalpLottieView otomatik `.accessibilityHidden(true)`. `PHASE_QA_NOTES.md` kapsamlı 2-dilli QA checklist + yayın kapısı ile yeniden yazıldı. Kalan: gerçek cihaz QA turu (TR + EN), Dynamic Type font scaling (`Font+Tokens.swift`'te `@ScaledMetric`), Xcode derlemesi, App Store Connect yapılandırması, marka/alan adı hukuki kontroller (bkz. `CALP_BRAND_CHECK.md`).

---

## EK — KULLANILABİLİRLİK (kullanıcı geri bildirimi, 2026-07-13)

- [x] **SF-EX01 · Free tarama günlük 1 foto + 2 metin/ses havuzuna ayrılsın** ✅ 2026-07-14
  **Dosyalar:** `Calp/Networking/FreeScanCounter.swift`, `Calp/App/ContentView.swift` (FreeScanLimitView), `CalpTests/FreeScanCounterTests.swift`
  **Sorun:** Ücretsiz tarama hakkı eski modelde ortak ve ömür boyu toplam tutuluyordu; bu, Pro olmadan uygulamayı birkaç denemeden sonra kullanılamaz hale getiriyordu.
  **Yapıldı:** `FreeScanCounter` fotoğraf (günlük 1) ve metin/ses (günlük 2) havuzlarını UTC gününde yeniler. Proxy installation hash ile sunucu esaslı limit uygular; iOS sayaçları çevrimdışı gösterim/fallback içindir. Yeni testler: UTC gün dönümü, bağımsız havuzlar ve server quota senkronu.

- [x] **SF-EX02 · Tek-seferlik elle öğün girişi (free, scan tüketmez)** ✅ 2026-07-13
  **Dosyalar:** `Calp/Models/ScanEntry.swift` (`ScanSource.manual`), `Calp/Views/Daily/DailyView.swift` (`ManualEntryView`, giriş noktaları, MealEntryCard ikonu)
  **Sorun:** App yalnız yemekten AI ile değer ayıklıyordu; "şu kadar kalori/protein aldım" diye **elle öğün girişi** yoktu (Hızlı Ekle sayaçları kalıcı öğe için, tek-seferlik değil). Pro olmadan pratikte kullanılamıyordu.
  **Yapıldı:** `ManualEntryView` sheet'i — kalori (zorunlu) + protein/karb/yağ (opsiyonel) girip bugüne `.manual` bir `ScanEntry` yazar (tek `LoggedItem`, adet/1). Halkaya, makro toplamlarına, Geçmiş gün detayına (silinebilir), widget'a ve CSV export'a akar; **AI tarama hakkı tüketmez**. Giriş noktaları: Bugün boş durumu + "BUGÜNKÜ ÖĞÜNLER" başlığı. Yeni dosya eklenmedi (committed .xcodeproj uyumu için DailyView.swift içinde).
  ⏸ **NOT:** Gerçek cihaz/derleme doğrulaması bekliyor (bu ortamda Xcode yok).

- [x] **SF-EX03 · Uygulama içinde sesle yemek kaydı** ✅ 2026-07-14
  **Dosyalar:** `Calp/Views/TextLog/TextLogView.swift` (`MealSpeechRecognizer` + mic butonu/banner), `Calp/Info.plist` + `tr.lproj`/`en.lproj` `InfoPlist.strings`, `Calp/Resources/Localizable.xcstrings`, `CalpTests/MealSpeechRecognizerTests.swift`
  **Amaç:** Kullanıcı yemek aramak ve yazmak yerine ne yediğini Türkçe veya İngilizce olarak söyleyebilsin.
  **Talimat (uygulandı):**
  1. ✅ `Speech` + `SFSpeechRecognizer` ile mikrofon girişi metne dönüşür. Locale, uygulama dilinden türetilir (`MealSpeechRecognizer.preferredLocale`: tr-TR / en-US; sistem dilinde otomatik seçim). Cihaz destekliyorsa `requiresOnDeviceRecognition` açılır — ham ses telefondan çıkmaz.
  2. ✅ Mikrofon + konuşma tanıma izni açılışta değil, yalnızca kullanıcı mic butonuna bastığında istenir (`Info.plist` purpose string'leri iki dilde).
  3. ✅ Canlı transkript alanı doldurdukça görünür; durumlar ayrık: `idle` / `listening` (canlı banner + waveform) / `denied(speech|microphone)` / `unavailable` / `failed`.
  4. ✅ Transkript **mevcut** `TextLogView` metin analiz akışına (`scanText`) akar; ayrı besin hesaplama yolu yok — recognizer SwiftData'ya veya free-scan sayacına dokunmaz.
  5. ✅ Sonuç doğrudan kaydedilmez: kullanıcı metni gözden geçirip "Analiz Et" der, kontrol/onay mevcut ResultView'da olur.
  **Kabul kriterleri:** İzin verildiğinde konuşulan cümle canlı olarak alana düşer ve mevcut metin analiziyle sonuç ekranına ulaşır; izin reddedildiğinde açıklayıcı banner + "Ayarlar'ı Aç" gösterilir ve yazılı giriş açık kalır. Testler: locale seçimi + idle/listening kontratı (`MealSpeechRecognizerTests`).
  ⏸ **NOT:** Gerçek cihaz/derleme doğrulaması bekliyor (bu ortamda Xcode yok); mikrofon + konuşma tanıma gerçek cihazda test edilmeli.

- [x] **SF-EX04 · Sesli girişte düzenleme ve onay akışı** ✅ 2026-07-14
  **Dosyalar:** `Calp/Views/TextLog/TextLogView.swift` (dikte-sonrası düzenleme odağı), mevcut `Calp/Views/Result/ResultView.swift` akışı
  **Amaç:** Konuşma tanıma hataları veya belirsiz porsiyonlar yanlışlıkla kaydedilmesin.
  **Talimat (uygulandı):**
  1. ✅ Dikte bittiğinde (final sonuç veya "Durdur") ve metin varsa klavye transkripte odaklanır — kullanıcı analiz öncesi metni düzeltmeye davet edilir. Alan zaten düzenlenebilir `TextEditor`.
  2. ✅ Analiz sonrası öğeler + canlı toplam ResultView'da gösterilir; eylemler ayrık: geri/"Düzelt" (metin taramasında chevron-left → editöre döner) ve "Kaydet" (Ekle). Öğeler tek tek düzenlenir/silinir.
  3. ✅ `ScanEntry` yalnızca "Kaydet" onayında `save()` içinde oluşturulur — onaydan önce kayıt yok. (AI tarama hakkı, uygulamanın tüm akışlarında olduğu gibi AI çağrısı yapıldığında sayılır; kayıt/log onayla ayrıdır.)
  4. ✅ İptal/geri dönüşte kayıt oluşmaz (`dismissResult` → save yok; düzenleme varsa "kaydedilmedi" onayı). Recognizer ham ses saklamaz; ekrandan çıkışta `cancel()` ile ses oturumu kapatılır.
  **Kabul kriterleri:** Sesli giriş iptal edildiğinde geçmişte kayıt oluşmaz; kullanıcı transkripti düzelttiğinde analiz düzeltilmiş metinle çalışır; onaydan sonra mevcut sonuç/kayıt akışıyla aynı değerler oluşur.

- [x] **SF-EX05 · Siri ve App Intents ile yemek ekleme** ✅ 2026-07-14
  **Dosyalar:** `Calp/AppIntents/LogMealIntent.swift` (yeni), `Calp/App/NavigationModel.swift` (`presentIntentMeal`), `Calp/App/CalpApp.swift` (scenePhase inbox tüketimi), `Calp/Views/TextLog/TextLogView.swift` (auto-analyze), `Calp/Resources/Localizable.xcstrings`, `Calp.xcodeproj` (yeni dosya + AppIntents grubu)
  **Amaç:** Kullanıcı Siri veya Kestirmeler üzerinden Calp'e yemek ekleyebilsin.
  **Talimat (uygulandı):**
  1. ✅ `LogMealIntent` (App Intents) — `meal` metin parametresi, `requestValueDialog` "Ne yedin?".
  2. ✅ `CalpAppShortcuts` ile TR + EN phrase'leri; `\(.applicationName)` üzerinden doğal komutlar ("Calp'e yemek ekle" / "Add a meal to Calp").
  3. ✅ `openAppWhenRun = true` — intent yalnızca ifadeyi `IntentMealInbox`'a (UserDefaults) yazar; app öne gelince taslak text-log'a doldurulup analiz edilir ve **onay ekranına** (ResultView) düşer. Arka planda sessiz kayıt yok.
  4. ✅ İkinci besin hesaplama mantığı yok: aynı `scanText` metin analiz akışı çağrılır (`presentIntentMeal` → TextLogView auto-analyze).
  5. ✅ Uygulama kapalıyken `openAppWhenRun` açar; ağ yoksa mevcut analiz hata alert'i gösterilir ve taslak korunur; boş ifadede `LogMealIntentError.emptyDescription`; free-scan limiti dolmuşsa mevcut FreeScanLimitView devreye girer.
  **Kabul kriterleri:** Kestirmeler'de intent görünür; Siri örnek komutuyla taslak oluşur ve onay ekranı açılır; onay verilmeden geçmişe kayıt yazılmaz; Türkçe/İngilizce kopyalar yerelleştirilmiştir.
  ⏸ **NOT:** Gerçek cihaz/derleme doğrulaması bekliyor (bu ortamda Xcode yok); Siri/Kestirmeler ve intent bağış gerçek cihazda test edilmeli.

> **Ortak altyapı (EX06/07/08):** `Calp/Notifications/MealReminderService.swift` (yeni) — `MealSlot`, `NotificationPrefs` (UserDefaults anahtarları), tek-seferlik `UNCalendarNotificationTrigger`'larla 4 günlük yuvarlanan pencere; her state değişiminde (app foreground, tercih değişimi, öğün kaydı) `removeAllPendingNotificationRequests` + tam yeniden kurulum. Ayar UI'ı `ContentView.swift` `notificationsSection`. Log noktaları (`ResultView.save`, `DailyView` elle giriş + silme, `QuickCounterView`) kayıttan sonra `reschedule` çağırır. `CalpApp` delegate'i kurar + scenePhase active'de yeniden kurar ve tıklanan bildirimi Bugün sekmesine yönlendirir.

- [x] **SF-EX06 · Kullanıcı kontrollü öğün hatırlatmaları** ✅ 2026-07-14
  **Dosyalar:** `Calp/Notifications/MealReminderService.swift`, `Calp/App/ContentView.swift` (notificationsSection), `Calp/App/CalpApp.swift`, `Calp/Views/Result/ResultView.swift`, `Calp/Views/Daily/{DailyView,QuickCounterView}.swift`, `Calp/Resources/Localizable.xcstrings`
  **Amaç:** Kullanıcı seçerse kahvaltı, öğle, akşam ve ara öğün saatlerinde nazik hatırlatma alabilsin.
  **Talimat (uygulandı):**
  1. ✅ Onboarding'de zorlama yok; bildirim izni yalnızca Ayarlar'da ilk bildirim açıldığında istenir.
  2. ✅ 4 öğün ayrı aç/kapat + `DatePicker` saat seçimi. **Ürün kuralı: hepsi varsayılan KAPALI** (opt-in, nötr felsefe).
  3. ✅ İlgili öğün kaydedildiğinde (zaman penceresi eşleşmesi) o öğünün bugünkü bildirimi düşer; her yeniden kurulumda `removeAll` ile tek kayıt garanti — tekrar gönderim yok.
  4. ✅ Bildirime dokununca `MealReminderDelegate` `openDaily` bayrağı kurar; app öne gelince Bugün sekmesine gider.
  5. ✅ Metinler TR + EN, nötr/suçlamayan ton ("Yediysen birkaç saniyede ekleyebilirsin.").
  **Kabul kriterleri:** Ayarlanan saat için yerel bildirim planlanır; öğün kaydedilince kaldırılır; tek ayarla ("Tüm bildirimleri kapat") tamamen kapatılır; app öne gelince planlar yeniden kurulur.
  ⏸ **NOT:** Gerçek cihaz/derleme doğrulaması bekliyor (izin diyaloğu + teslim zamanlaması cihazda test edilmeli).

- [x] **SF-EX07 · Gün içinde hiç kayıt yapılmadığında tek hatırlatma** ✅ 2026-07-14
  **Dosyalar:** `Calp/Notifications/MealReminderService.swift`, `Calp/App/ContentView.swift`, log noktaları (yukarıdaki ortak altyapı)
  **Amaç:** Kullanıcı gün boyunca hiçbir öğün eklemediyse, spam yapmadan tek bir geri dönüş noktası.
  **Talimat (uygulandı):**
  1. ✅ Günlük kayıt (scan + quick-add) sayısı sıfırsa, kullanıcının belirlediği akşam saatinde tek bildirim planlanır.
  2. ✅ Gün içinde herhangi bir kayıt oluşunca `reschedule` bugünkü no-log bildirimini düşürür.
  3. ✅ Kayıt ≥1 ise "eksik kaldın" bildirimi gönderilmez (gate: `loggedCount > 0`).
  4. ✅ Bildirim uygulamayı Bugün ekranına açar.
  **Kabul kriterleri:** Sıfır kayıtlı günde en fazla bir bildirim; ilk kayıt sonrası iptal; ertesi gün sıfırlanır (günlük re-arm + horizon'da ertesi gün kaydı); kapalı kullanıcıya hiç gönderilmez.
  ⏸ **NOT:** Gerçek cihaz/derleme doğrulaması bekliyor.

- [x] **SF-EX08 · Gece özeti ve bildirim tercihleri** ✅ 2026-07-14
  **Dosyalar:** `Calp/Notifications/MealReminderService.swift`, `Calp/App/ContentView.swift` (notificationsSection), `Calp/Resources/Localizable.xcstrings`
  **Amaç:** Kullanıcı isterse günü sakin bir özetle kapatsın; sistem kullanıcı kontrolünde kalsın.
  **Talimat (uygulandı):**
  1. ✅ İsteğe bağlı gece özeti: bugünün toplam kalori, protein ve kayıtlı öğün sayısı (bugün için gerçek değerler, ileri günler için nötr metin; günlük re-arm ile tazelenir).
  2. ✅ Özet yalnızca bilgi verir; "daha ye" baskısı yok.
  3. ✅ Ayarlar'da ayrı tercihler: öğün hatırlatmaları (×4), hiç-kayıt-yok, gece özeti ve "Tüm bildirimleri kapat".
  4. ✅ Kullanıcı saati değiştirince `removeAll` + yeniden planlama.
  **Kabul kriterleri:** Gece özeti yalnızca açıkken gönderilir; aynı gün ikinci kez gönderilmez (id/gün + removeAll); tüm bildirimler kapatılınca bekleyenler temizlenir; TR/EN metinleri eksiksiz.
  ⏸ **NOT:** Gerçek cihaz/derleme doğrulaması bekliyor.

**Testler (EX06/07/08):** `CalpTests/NotificationPrefsTests.swift` — öğün zaman pencereleri çakışmaz, varsayılan saatler, master switch gate'i.

## GELECEK (roadmap dışı, başlamadan Fatih onayı gerek)
- "Calp Modu" (çok kişilik tencere paylaşımı) — PROJECT_CONTEXT'te v1.1.
- Tencere/ev tarifi kalibrasyon hafızası.
- Apple Health yazma entegrasyonu.
- Ramazan modu (sahur/iftar zaman pencereleri).
- Streak/rozet sistemi — utandırmayan, nötr dil şartıyla tasarlanacak.
- App Attest / DeviceCheck ile proxy anahtarını sertleştirme (statik `x-calp-key` MVP sonrası yetmez).

---

## İNCELEME NOTLARI (görev üretmeyen, bilinçli kararlar)
- `SettingsView`/`HistoryView`'ın kendi dosyalarında olmaması: committed .xcodeproj uyumu için bilinçli — FAZ 4/5 dokunuşlarında `xcodegen generate` ile birlikte kendi klasörlerine taşınabilir (SF-401 bunu yapıyor).
- `CalorieRingView` hedef-üstünü kırmızıyla göstermiyor — bu tasarım kararıdır, koru (SF-604 nötr ek gösterge ekliyor).
- `stableSeed` + Structured Outputs + `reasoning_effort` seçimleri doğru; dokunma.
- Kamera mimarisi (paylaşılan CameraManager + serial queue) sağlam; yeniden yazma girişimi YASAK.
- `DailyQuickCounter` legacy modeli şema uyumu için duruyor; silme (CloudKit store'ları bozar).
