# SCOPES_PLAN — Fiyatlandırma, Limitler, Analitik ve Ürün Geliştirme Uygulama Planı

> Kaynak: "CALORISOR — FİYATLANDIRMA, KULLANIM LİMİTLERİ, ANALİTİK ALTYAPISI VE ÜRÜN GELİŞTİRME PLANI"
> (scopes.md, 14 Temmuz 2026). Bu dosya o dokümanın 30. bölümündeki talimat gereği
> repo incelemesi sonrası çıkarılmış **dosya bazlı uygulama planıdır**.
> Görev formatı ROADMAP.md ile aynıdır (SF-XXX, kabul kriterleri, fazlar).
> ROADMAP.md FAZ 0–10'u kapsar; bu plan FAZ 11–15 olarak devam eder.
> Kaynak dokümandaki Faz 1–5 ↔ buradaki FAZ 11–15 birebir karşılıktır.

---

## 1. Repo eşleştirmesi (kaynak doküman §30)

| Gereksinim | Repo karşılığı | Durum |
|---|---|---|
| Vercel proxy endpoint | `proxy/api/scan.ts` (Edge runtime) | Var — deploy edilmiş, istemci bağlı |
| StoreKit manager | `Calorisor/StoreKit/StoreKitManager.swift` | Var |
| Paywall view | `Calorisor/Views/Onboarding/PaywallView.swift` | Var |
| StoreKit configuration | `Calorisor/StoreKit/Products.storekit` | Var |
| Info.plist | `Calorisor/Info.plist`, `CalorisorWidget/Info.plist` | Var |
| SwiftData modelleri | `Calorisor/Models/` (LoggedItem, ScanEntry, UserProfile, DailyQuickCounter) + `Persistence/CalorisorModelContainer.swift` | Var |
| Günlük öğün ekranı | `Calorisor/Views/Daily/DailyView.swift` (kabuk: `App/ContentView.swift`) | Var |
| Widget data store | `Calorisor/Models/WidgetDataStore.swift` + `Extensions/WidgetDataStore+MainApp.swift` + `CalorisorWidget/` | Var |
| Notification service | `Calorisor/Notifications/MealReminderService.swift` | Var |
| CSV export | `Calorisor/Models/DataExporter.swift` | Var |
| Settings screen | `SettingsView`, `Calorisor/App/ContentView.swift` içinde (ayrı dosya değil) | Var |
| Ses girişi | `MealSpeechRecognizer`, `Calorisor/Views/TextLog/TextLogView.swift` içinde — transkript text akışına akıyor | Var |
| Free limit sayacı | `Calorisor/Networking/FreeScanCounter.swift` | Var ama modeli farklı (aşağıda) |
| Installation ID / Keychain | — | **Yok** (repo'da hiç Keychain kullanımı yok) |
| Usage/maliyet logu | — | **Yok** (proxy `usage` alanını parse etmiyor) |
| Signed transaction doğrulama | — | **Yok** (tier istemci beyanı) |
| HealthKit | — | **Yok** |
| Haftalık AI raporu | — | **Yok** |
| Hızlı tekrar ekleme / favoriler | — | **Yok** (`DailyQuickCounter` ekmek/çay sayacıdır, bu özellik DEĞİLDİR) |
| Proxy testleri | — | **Yok** (`proxy/` altında test altyapısı yok; iOS testleri `CalorisorTests/` güçlü) |

---

## 2. Mevcut durum ↔ hedef durum farkları (doğrulanmış bulgular)

### 2.1 Free limit modeli çelişiyor
- Mevcut: `FreeScanCounter` **haftalık 3 tarama**, foto+metin ortak havuz, UserDefaults'ta, tamamen cihaz-yerel (`FreeScanCounter.swift:28`, `ContentView.swift:214`).
- Hedef: **günlük 1 foto + günlük 2 metin/ses** (ayrı havuzlar), esas uygulama **sunucuda** installation hash ile, UTC günü.
- `CalorisorTests/FreeScanCounterTests.swift` haftalık rollover'a göre yazılmış — model değişince yeniden yazılacak.

### 2.2 Proxy'de kullanım limiti yok, tier doğrulanmıyor
- `proxy/api/scan.ts:294-299`: yalnız IP-hash bazlı 10/dk + 200/gün genel rate limit var. Tier bazlı günlük hak yok.
- `scan.ts:326`: model seçimi doğrudan istemcinin gönderdiği `tier` alanından — jailbreak/proxy manipülasyonuyla bedava gpt-5-mini alınabilir.

### 2.3 Cache key eksik ayrıştırıyor (aktif hata)
- `scan.ts:198`: key = `calorisor:scan:v2:{mode}:{sha256(input)}`. **Model/tier, locale ve prompt sürümü key'de yok.**
- Sonuç 1: Free'nin nano sonucu Pro kullanıcıya cache'ten dönebilir (dokümanın §12'de uyardığı durum bugün gerçek).
- Sonuç 2: Aynı input'un TR locale cevabı EN kullanıcıya dönebilir (promptlar locale'e göre farklı ama key değil).

### 2.4 "Sınırsız" ifadeleri (kaldırılacak yerlerin tam listesi)
- `Calorisor/Views/Onboarding/PaywallView.swift:135-136` — "Sınırsız fotoğrafla kalori takibi", "Sınırsız yazarak öğün ekleme"
- `Calorisor/App/ContentView.swift:214,222` — limit sheet metni + "Sınırsız Taramaya Geç" butonu
- `Calorisor/StoreKit/Products.storekit:23,49` — iki ürün açıklaması
- `Calorisor/Resources/Localizable.xcstrings` — yukarıdakilerin EN/TR karşılıkları
- `PHASE_QA_NOTES.md:122` — "Unlimited photo calorie tracking..." QA satırı
- Gerçekten sınırsız olanlar (manuel kayıt, geçmiş, düzenleme) için kelime serbest (§7).

### 2.5 StoreKit konfigürasyonu
- `Products.storekit`: aylık 129,99 / yıllık 799,99 (lansman fiyatları ✓), yıllıkta P1W ücretsiz deneme ✓, aylıkta deneme yok ✓.
- **`familyShareable: false`** — doküman Family Sharing açılmasını istiyor (§18.3). Hem local config hem ASC'de açılacak.
- Bayat metinler: `StoreKitManager.swift:9` "3-day intro trials" yorumu; `PROJECT_CONTEXT.md` hâlâ "3-day trial", "lifetime 3 scans", "Gemini Flash" diyor (kod OpenAI gpt-5 ailesinde).

### 2.6 Request sözleşmesi eksikleri
- `AIProxyClient.swift:52-105` (`AIProxyRequest`): `input_source` yok (ses, text olarak gidiyor — voice/typed ayrımı sunucuya ulaşmıyor), installation header'ları yok, `claimed_tier`/JWS alanları yok.
- Proxy `isScanRequest` (`scan.ts:201-230`) `schema_version === 1`'e sabitlenmiş; bilinmeyen alanları yok saydığı için alan EKLEMEK geriye uyumlu, alan zorunlu kılmak eski istemcileri kırar. Yeni alanlar opsiyonel başlamalı.

### 2.7 Ölçüm/loglama sıfır
- `scan.ts:22-28` `OpenAIChatResponse` tipinde `usage` alanı bile yok; token, maliyet, response time, request_id, cache metrikleri hiçbir yerde tutulmuyor.
- DİKKAT: `AIProxyClient.swift:11-12` ve `MODEL_RESEARCH.md`'deki fiyat yorumları ("$0.25/$0.025", "$0.05/$0.005") **hatalı görünüyor** (output fiyatı input'tan ucuz olamaz; resmi liste: nano $0.05/$0.40, mini $0.25/$2.00 per 1M). `MODEL_PRICING` doldurulurken deployment günü resmi sayfadan doğrula (§14).

### 2.8 Hata sözleşmesi dar
- Proxy yalnız `rate_limited | invalid_request | upstream_error` dönüyor (`scan.ts:128-139`); istemci `mappedProxyError` (`AIProxyClient.swift:589`) bilinmeyen hataları `scanFailed`'e düşürüyor → yeni hata türleri (daily_limit_reached, subscription_required, …) geriye uyumlu eklenebilir ama istemci ayrımı için istemci de güncellenecek.

### 2.9 ROADMAP.md ile koordinasyon
- SF-201/202/203 (proxy iskeleti/Upstash/istemci bağlama) "⏸ hesap bekliyor" durumda ama kod deploy edilmiş (`751d3ae config: point app at deployed AI proxy`). FAZ 11 proxy görevleri aynı dosyaların üstüne gelir — önce SF-201..203'ün notları kapatılmalı/güncellenmeli.
- SF-504 (abonelik yönetimi) ve SF-505 (yıllık/12 format) paywall görevleriyle kesişir; SF-1107 ile birlikte ele alınabilir.

---

## 3. Sabitlenen kararlar (kaynak dokümandan)

1. Gün başlangıcı: **UTC** (§11.5). iOS'ta kalan hak gösterimi de aynı UTC hesabını kullanır.
2. Haftalık abonelik hiçbir pazarda yok; deneme yalnız yıllıkta, 7 gün.
3. Fiyatlar: TR lansman 129,99/799,99 → standart 149,99/899,99; global 6,99/29,99 USD. ASC girişleri manuel iştir (aşağıda "manuel işler").
4. Free: günde 1 foto + 2 metin/ses (ses ve metin AYNI havuz, foto AYRI). Pro: 50 foto + 100 metin/ses.
5. `claimed_tier` yalnız geçiş dönemi; kalıcı çözüm StoreKit 2 JWS doğrulaması (FAZ 13).
6. Ham installation ID, ham IP, fotoğraf, tam metin/prompt/cevap, sağlık verisi ASLA loglanmaz (§13.2).
7. Maliyet integer **microusd** saklanır.
8. PROJECT_CONTEXT.md'nin dokunulmaz kuralları geçerli: hesap yok, Supabase yok, RevenueCat yok, barkod yok; kullanıcı verisi SwiftData+CloudKit'te kalır. HealthKit verisi backend'e gitmez.

---

## FAZ 11 — YAYIN ÖNCESİ KRİTİK (kaynak Faz 1)

- [ ] **SF-1101 · InstallationIdentity: Keychain'de anonim kurulum kimliği** ⏸ NOT: Kod + testler yazıldı ve pbxproj'a elle eklendi; `xcodebuild test` Mac'te doğrulanacak (Linux ajan ortamında Xcode yok).
  **Dosya:** yeni `Calorisor/Networking/InstallationIdentity.swift`, test `CalorisorTests/InstallationIdentityTests.swift`
  **Talimat:** İlk erişimde UUID üret, Keychain'e `com.fatih.calorisor.installation-id` anahtarıyla yaz (kSecClassGenericPassword, ThisDeviceOnly erişilebilirlik). UserDefaults KULLANMA. Okuma başarısızsa yeni UUID üret (silme sonrası kalıcılık garanti edilmez, §8.1). Keychain erişimi test edilebilir olsun (protokolle soyutla).
  **Kabul:** ID bir kez üretilir, ikinci okuma aynı değeri döner; mock-keychain testleri geçer.
  **Uygulama notu:** `InstallationKeychainStore` protokolü + `SystemKeychainStore` (AfterFirstUnlockThisDeviceOnly) + kilitli/cache'li `InstallationIdentity` sınıfı (`.shared`, `headerValue` SF-1102 için hazır). Testler in-memory + write-count spy ile: tek üretim, kalıcılık (ayrı instance aynı değeri okur), bozuk değerin yenilenmesi, ayrı kurulumların farklı ID'si.

- [ ] **SF-1102 · İstemci request sözleşmesi: input_source + header'lar + claimed_tier** ⏸ NOT: Kod + testler yazıldı; `xcodebuild test` Mac'te doğrulanacak. Yeni dosya yok, pbxproj değişmedi.
  **Dosya:** `Calorisor/Networking/AIProxyClient.swift`, `Calorisor/Views/TextLog/TextLogView.swift`, `CalorisorTests/AIProxyRequestTests.swift`
  **Talimat:** `AIProxyRequest`'e `input_source: "photo"|"typed_text"|"voice_transcript"` ekle; TextLog akışı transkript kullanıldıysa `voice_transcript` göndersin (MealSpeechRecognizer'dan gelen metin `textInput`'a yansıyor — son analiz girdisinin kaynağını izle). Geçiş için body'de hem `tier` (eski) hem `claimed_tier` gönder. Header'lar: `x-calorisor-installation-id` (ham UUID), `x-calorisor-app-version`, `x-calorisor-platform: ios` (`x-calorisor-key` zaten var). Installation ID body'ye KONMAZ.
  **Kabul:** Encode edilen JSON ve header'lar testle doğrulanır; eski proxy'ye karşı geriye uyumlu (yeni alanlar eklenince mevcut deploy 400 dönmüyor — `isScanRequest` bilinmeyen alanı umursamıyor, doğrulanacak).
  **Uygulama notu:** `AIProxyInputSource` enum'u; `AIProxyRequest`'e `input_source` + `claimed_tier` (=tier). `scanText(_:inputSource:)` (varsayılan `.typedText`). Header'lar `performProxyRequest`'te `InstallationIdentity.shared.headerValue` ile eklendi (hem foto hem text yolunda). TextLogView `usedDictation` bayrağı: transkript gelince true, alan boşalınca / öneri dokununca false → `scan()` `voice_transcript`/`typed_text` seçer. **Geriye uyumluluk doğrulandı:** deploy'daki `isScanRequest` yalnız mevcut alanları doğruluyor, `tier` hâlâ gönderiliyor, `JSONEncoder` nil `image_base64`'ü atlıyor → 400 yok. Testler: `input_source`/`claimed_tier` (typed/voice/photo) encode + mock-URLProtocol header + installation ID'nin gövdede olmadığı.

- [x] **SF-1103 · Proxy: installation hash** ✅ 2026-07-14
  **Dosya:** `proxy/api/scan.ts`, `proxy/.env.example`, `proxy/README.md`
  **Talimat:** `x-calorisor-installation-id` header'ını al; `SHA256(installation_id + INSTALLATION_HASH_SALT)` üret (`INSTALLATION_HASH_SALT` yeni Vercel env). Ham ID hiçbir log/Redis değerine yazılmaz; her yerde yalnız `installation_hash` kullanılır. Header yoksa: eski sürümler için IP-hash fallback'iyle çalışmaya devam et (geçiş dönemi), yeni app_version'larda `invalid_request`.
  **Kabul:** Salt olmadan boot hatası değil kontrollü 502; hash deterministik; ham ID grep'le hiçbir çıktıda yok.
  **Uygulama notu:** `limitIdentity()` yardımcısı: header varsa `sha256(id + salt)` (source "installation"), yoksa `sha256(ip)` (source "ip"). Salt env yoksa handler üstünde kontrollü 502 (OpenAI key kontrolüyle aynı desen). Rate-limit anahtarı artık `identity.key` (ipHash yerine). "Yeni sürümde zorunlu" kısmı kırılgan semver yerine `REQUIRE_INSTALLATION_ID=true` env bayrağıyla (varsayılan kapalı → IP fallback; açılınca header'sız istek 400). `.env.example` + README güncellendi. **Doğrulama:** `npm run typecheck` (tsc --noEmit) temiz geçti; `grep console.` → hiç log yok, ham ID yalnız hash girdisinde. Otomatik proxy senaryoları SF-1204 Vitest harness'ında doğrulandı.
  **⚠ Deploy notu:** Bu kod canlıya çıkmadan ÖNCE Vercel'de `INSTALLATION_HASH_SALT` set edilmeli, aksi halde endpoint tüm isteklere 502 döner (kasıtlı — SF-1110).

- [x] **SF-1104 · Proxy: cihaz bazlı günlük limitler (Free 1+2, Pro 50+100)** ✅ 2026-07-14
  **Dosya:** `proxy/api/scan.ts`
  **Talimat:** UTC gününe göre `calorisor:usage:{date}:{installation_hash}:photo|text` sayaçları (INCR + 48h EXPIRE). `input_source: voice_transcript` **text havuzunu** tüketir. Limitler: free photo 1 / text 2; pro photo 50 / text 100. 10/dk minüt limiti ortak kalır; IP limiti ikincil sinyale iner (ana kimlik installation_hash). Aşımda 429 + gövde `{"error":"daily_limit_reached","limit_type":"photo|text","tier":"...","remaining":0}`. Başarılı cevaplara header'lar: `x-calorisor-tier`, `x-calorisor-photo-remaining/-limit`, `x-calorisor-text-remaining/-limit` (§16). Cache hit de hak TÜKETMEZ (önce limit mi cache mi: cache-hit bedavadır → önce cache bak, hit ise sayaç artırma).
  **Kabul:** §27 senaryoları: free foto 2. istek limit; free text 3. istek limit; voice text havuzunu düşürüyor; pro 51. foto limit; cache hit sayaç artırmıyor.
  **Uygulama notu:** `DAILY_LIMITS` sabiti (free 1/2, pro 50/100); havuz `mode`'dan (`photo`→photo, `text`→text, voice zaten mode text). Eski 200/gün IP sliding-window kaldırıldı, 10/dk kaldı. Akış: dakika limiti + `mget(photoKey,textKey)` tek turda → cache hit ise header'larla dön (INCR yok) → miss'te `used >= limit` kontrolü → OpenAI → **başarıdan sonra** `incr` (+ ilk yazımda 48h expire). Başarısız tarama / limit / cache hit hak yakmaz. `daily_limit_reached` gövdesi + §16 header'ları. Sayaç hatası taramayı düşürmez (fallback tahmin). Otomatik doğrulama: `proxy/api/scan.test.ts` içinde free foto/text limitleri, ayrı havuzlar ve cache-hit quota davranışı.

- [x] **SF-1105 · Proxy: cache key v3 (model + locale + prompt_version ayrımı)** ✅ 2026-07-14
  **Dosya:** `proxy/api/scan.ts`, `proxy/prompts.ts`
  **Talimat:** Key: `calorisor:scan:v3:{mode}:{locale}:{model}:{prompt_version}:{input_hash}`. `PROMPT_VERSION` sabitini `prompts.ts`'e koy (SF-104 istemci tarafında prompt sürümü hazırlamıştı — uyumlu isimlendir). Nano ve mini sonuçları ayrışır; v2 anahtarları doğal TTL ile ölür.
  **Kabul:** Aynı input free/pro için farklı key üretir (test); locale değişince key değişir; cache hit'te OpenAI çağrısı yok.
  **Uygulama notu:** `PROMPT_VERSION = 1` `prompts.ts`'te export (prompt metni değişince bump → cache bypass). İstemcide prompt_version yoktu (SF-104 yalnız `schema_version` eklemişti), cache sunucu-taraflı olduğundan tek kaynak sunucu. `modelForTier(tier)` tek yerde model seçiyor; `model` handler üstünde bir kez hesaplanıp hem `cacheKey(body, model)`'e hem OpenAI fetch'ine gidiyor (önceki inline `body.tier === "pro" ? ...` ikilemesi kaldırıldı). **Düzeltilen aktif bug:** v2 key'i model/locale içermediğinden free-nano sonucu pro-mini kullanıcıya (ve TR cevabı EN kullanıcıya) cache'ten dönebiliyordu. Deploy sonrası ilk istekler v3 miss (yeniden dolar), v2 doğal TTL ile ölür. Otomatik doğrulama: Vitest cache-key ayrımı, locale ayrımı ve aynı anahtarda OpenAI çağrısının tekrarlanmaması.

- [ ] **SF-1106 · iOS: FreeScanCounter'ı günlük 1 foto + 2 metin/ses modeline geçir, sunucu esas**
  **Dosya:** `Calorisor/Networking/FreeScanCounter.swift`, `Calorisor/Networking/AIProxyClient.swift`, `Calorisor/App/ContentView.swift`, `CalorisorTests/FreeScanCounterTests.swift`
  **Talimat:** İki ayrı günlük havuz (photo:1, textOrVoice:2), gün sınırı **UTC** (Calendar(identifier:.gregorian)+UTC). Proxy cevabındaki `x-calorisor-*-remaining` header'larını okuyup yerel sayacı sunucu değerine eşitle (sunucu esas, yerel değer yalnız gösterim/çevrimdışı tahmin). `daily_limit_reached` gövdesi yeni `AIProxyError.dailyLimitReached(limitType:)`'e map edilir. Limit UX metinleri §17'deki kopyalarla: foto bitti / metin-ses bitti ayrı mesajlar; manuel giriş asla engellenmez; sheet agresif değil (Kısa açıklama · "Manuel ekle" · "Pro'yu incele" · Kapat).
  **Kabul:** Eski haftalık testler silinip günlük testlerle değiştirilir; UTC gün dönümü testi; limitte manuel girişin açık kaldığı test/preview; header senkron testi (mock URLProtocol, SF-902 altyapısı).

- [ ] **SF-1107 · "Sınırsız" temizliği + paywall şeffaflık kopyası**
  **Dosya:** `PaywallView.swift`, `ContentView.swift`, `Products.storekit`, `Localizable.xcstrings`, `PHASE_QA_NOTES.md`
  **Talimat:** §2.4'teki tüm satırları değiştir. Yeni kopyalar (§6.2/§7): "Günlük kullanım için yüksek limitli AI analizi", "Pro ile daha fazla analiz"; buton "Pro'yu İncele". Paywall'da §5 zorunluları: yıllık TOPLAM fiyat aylık eşdeğerden daha görünür; deneme sonunda tahsil edilecek gerçek tutar; otomatik yenileme + App Store'dan iptal cümlesi (mevcut "Sonra {fiyat} · istediğin an iptal" satırını §5 örneğine genişlet). "Yalnızca X TL/ay" tek başına kullanılmaz. SF-505'in aylık-eşdeğer format düzeltmesini burada birlikte kapat. EN/TR ikisi de güncellenir.
  **Kabul:** Repo'da `grep -ri "sınırsız\|unlimited"` yalnız gerçekten sınırsız özellikler (manuel kayıt/geçmiş/düzenleme) ve kod-içi `hasUnlimitedScans` gibi teknik adlarda kalır (o property da yeniden adlandırılır); paywall snapshot/preview güncel.

- [ ] **SF-1108 · Products.storekit: Family Sharing + açıklama metinleri**
  **Dosya:** `Calorisor/StoreKit/Products.storekit`
  **Talimat:** İki üründe `familyShareable: true`; açıklamalardan "Sınırsız" çıkar (SF-1107 ile aynı terminoloji). Fiyatlar lansman değerlerinde kalır (129,99/799,99 — §4.2). Deneme: yalnız yıllıkta P1W ✓ (değişiklik yok).
  **Kabul:** StoreKit config testte yüklenir; paywall Family Sharing'i belirtir (SF-1107 kopyasına satır ekle).

- [ ] **SF-1109 · Bayat doküman/yorum düzeltmeleri**
  **Dosya:** `StoreKitManager.swift` (satır 9 "3-day"), `PROJECT_CONTEXT.md` ("3-day trial", "lifetime 3 scans", "Gemini Flash"), `ROADMAP.md` (SF-201..203 durum notları)
  **Talimat:** Gerçek durumla eşitle: 7 gün deneme yalnız yıllıkta; free limiti günlük 1+2; model OpenAI gpt-5-nano/mini; proxy deploy edilmiş.
  **Kabul:** `grep -ri "3-day\|3 gün deneme\|gemini"` temiz (tarihî PHASE notları hariç).

- [ ] **SF-1110 · Manuel işler kontrol listesi (kod dışı — Fatih)**
  App Store Connect: TR fiyatları (lansman 129,99/799,99; sonrası 149,99/899,99), global 6,99/29,99 USD; haftalık plan EKLEME; yıllık 7g deneme; Family Sharing aç; App Store açıklamasında "sınırsız AI" ifadesi kullanma. OpenAI: ayrı project, hard/soft budget + günlük harcama alarmı (§22.3). Vercel: `INSTALLATION_HASH_SALT` env'i. Privacy Policy + Terms metinlerini §23'e göre güncelle ("hiç veri toplamıyoruz" deme; installation hash, 7 gün cache, token/maliyet kaydı, AI sonuçları tahminidir, adil kullanım).

---

## FAZ 12 — ÖLÇÜM VE GÖZLEMLENEBİLİRLİK (kaynak Faz 2)

- [ ] **SF-1201 · Usage parse + maliyet hesabı + request_id**
  **Dosya:** `proxy/api/scan.ts`
  **Talimat:** `OpenAIChatResponse`'a `usage` alanını ekle (§14 tipi). `MODEL_PRICING` sabiti (deployment günü resmi fiyatlarla doldur — §2.7'deki yorum hatasına dikkat). `estimated_cost_microusd` integer hesapla. Her isteğe `crypto.randomUUID()` request_id; `response_time_ms`, `openai_response_time_ms`, `redis_lookup_time_ms` ölç. Cache hit'te token=0, cost=0, cache_status=hit (§12). `usage` alanı yoksa loglama çökmez.
  **Kabul:** §27: "Usage alanı yoksa sistem çökmüyor", "Cache hit cost 0", "Token maliyet hesabı doğru" (birim test).

- [ ] **SF-1202 · Redis günlük aggregate metrikler + kısa request log**
  **Dosya:** `proxy/api/scan.ts` (veya yeni `proxy/lib/metrics.ts`)
  **Talimat:** §15.1 key seti: `metrics:{date}:requests:total|free|pro`, `mode:photo|text`, `source:voice`, `cache:hit|miss`, `tokens:input|output`, `cost:microusd`, `status:error`, `rate_limited` (INCRBY + 35 gün EXPIRE). Son istekler `calorisor:request-logs` list/stream'ine §13.1 zorunlu alanlarla (LPUSH+LTRIM ~1000, retention 7–30 gün). §13.2 yasak alanlar (foto, base64, tam metin, prompt, cevap, ham IP, ham installation ID) ASLA yazılmaz; izinli metadata: input karakter sayısı, image byte size, item count, average_confidence, no_food_detected.
  **Kabul:** Bir istek sonrası tüm sayaçlar artar; log kaydında yasaklı alan olmadığı testle taranır.

- [ ] **SF-1203 · Hata türlerini standardize et (proxy + istemci)**
  **Dosya:** `proxy/api/scan.ts`, `Calorisor/Networking/AIProxyClient.swift`, `CalorisorTests/AIProxyClientErrorTests.swift`
  **Talimat:** §16 error seti: `invalid_request, unauthorized, rate_limited, daily_limit_reached, subscription_required, subscription_verification_failed, upstream_error, service_unavailable`. Geçersiz client key artık `unauthorized` (401) döner (bugün `invalid_request` dönüyor — istemci mapping'i iki değeri de tanısın). `mappedProxyError` yeni türleri ayrıştırır.
  **Kabul:** §27 "Geçersiz client key → 401"; her hata türü için istemci map testi.

- [x] **SF-1204 · Basit rapor script'i + proxy test altyapısı** ✅ 2026-07-14
  **Dosya:** yeni `proxy/scripts/daily-report.ts`, `proxy/package.json` (vitest), yeni `proxy/api/scan.test.ts`
  **Talimat:** Metrik key'lerini okuyup günlük özet basan script (istek/maliyet/cache oranı/free-pro dağılımı — §25 teknik metrikleri). Vitest kur; §27 proxy senaryolarını mock Redis/OpenAI ile otomatikleştir (SF-1104/1105/1201/1203 kabul testleri buraya taşınır/toplanır).
  **Kabul:** `npm test` proxy dizininde §27 proxy listesini koşuyor. ✅ `proxy/api/scan.test.ts`: 4/4 senaryo geçti; `npm run typecheck` temiz.

---

## FAZ 13 — GELİR GÜVENLİĞİ (kaynak Faz 3)

- [ ] **SF-1301 · iOS: signed transaction (JWS) gönderimi**
  **Dosya:** `StoreKitManager.swift`, `AIProxyClient.swift`
  **Talimat:** `Transaction.currentEntitlements`'tan aktif aboneliğin `jwsRepresentation`'ını al; `AIProxyRequest.signed_transaction_info` olarak ekle (yalnız Pro iddiasında). Offline'da istemci kendi entitlement'ını kullanır; proxy erişilebilirken sunucu kararı esastır (§10.2).
  **Kabul:** Request encode testi; abonesiz kullanıcıda alan hiç gönderilmez.

- [ ] **SF-1302 · Proxy: Apple JWS doğrulama + entitlement cache**
  **Dosya:** yeni `proxy/lib/entitlement.ts`, `proxy/api/scan.ts`
  **Talimat:** JWS x5c zincirini Apple Root CA'ya karşı doğrula; `productID ∈ {com.fatih.calorisor.monthly, com.fatih.calorisor.annual}`, `expirationDate > now`, `revocationDate == null` kontrolü. Sonuç `calorisor:entitlement:{installation_hash}` key'inde 15 dk–1 saat TTL ile cache'lenir. Doğrulama başarısızsa tier=free + `subscription_verification_failed` sinyali (istek free limitleriyle devam eder, hard-fail değil).
  **Kabul:** §27: expired→free, revoked→free, geçerli monthly/annual→pro (test vektörleriyle).

- [ ] **SF-1303 · claimed_tier bağımlılığını kaldır**
  **Dosya:** `proxy/api/scan.ts`, `Calorisor/Networking/AIProxyClient.swift`
  **Talimat:** Model ve limit seçimi yalnız sunucu tier'ından. `claimed_tier` yalnız eski app_version'lar için okunur; sunset sürümü belirle. İstemciden `tier` alanını kaldır.
  **Kabul:** `claimed_tier: "pro"` + geçersiz/eksik JWS → nano model + free limitleri (test).

- [ ] **SF-1304 · Anomali alarmları + App Attest hazırlığı**
  **Dosya:** `proxy/api/scan.ts` / `metrics.ts`; tasarım notu `SCOPES_PLAN.md`'ye ek
  **Talimat:** §22.4 sinyalleri: tek installation'dan aşırı istek, invalid key sayısı, verification hata sayısı, günlük maliyet eşiği → `metrics:{date}:anomaly:*` sayaçları + rapor script'inde eşik uyarısı. App Attest (§22.2) için akış tasarımını yaz, implementasyon kullanıcı sayısı artınca.
  **Kabul:** Eşik aşımı rapor çıktısında UYARI satırı üretir.

---

## FAZ 14 — RETENTION: HIZLI TEKRAR EKLEME (kaynak Faz 4)

- [ ] **SF-1401 · Normalize öğün kimliği + sık eklenenler hesaplayıcı**
  **Dosya:** yeni `Calorisor/Models/FrequentMealsBuilder.swift`, test
  **Talimat:** İlk sürümde ayrı FavoriteMeal @Model'i YOK (§19.3): son 30 günün kayıtlarını normalize kimlikle grupla — lowercased adlar + sıralı item adları + porsiyon birimi + yuvarlanmış miktar → SHA256 (§19.4). Kullanım sayısına göre ilk 5.
  **Kabul:** Aynı öğünün farklı sıralı itemları aynı kimliği üretir; birim testleri.

- [ ] **SF-1402 · Bugün ekranına "Sık Eklenenler" + tek dokunuş derin kopya**
  **Dosya:** `Calorisor/Views/Daily/DailyView.swift`, ilgili modeller
  **Talimat:** Kart: öğün adı, toplam kalori, son kullanım, ekle butonu. Eklemede **derin kopya** yeni SwiftData kaydı (eski kaydın referansı tekrar KULLANILMAZ, §19.5); AI çağrısı YAPILMAZ; widget özeti (`WidgetDataStore`) ve `MealReminderService` güncellenir; CloudKit senkronu bozulmaz.
  **Kabul:** §19.6 kriterlerinin tamamı: bağımsız nesne, eski kayıt değişmez, makrolar aynen, porsiyon eklemeden önce değiştirilebilir, proxy çağrısı yok, widget/bildirim güncel.

- [ ] **SF-1403 · Widget ve Siri quick-add**
  **Dosya:** `CalorisorWidget/`, `Calorisor/AppIntents/LogMealIntent.swift`
  **Talimat:** SF-701'in QuickAdd modeli üstüne: widget'tan sık eklenen öğünü tek dokunuşla ekleme; `LogMealIntent`'i favori/sık eklenen parametresiyle genişlet.
  **Kabul:** Widget'tan ekleme AI çağrısı yapmaz; günlük özet anında yenilenir.

---

## FAZ 15 — ÜRÜN DEĞERİ: HEALTHKIT + HAFTALIK RAPOR (kaynak Faz 5)

- [ ] **SF-1501 · HealthKit temel entegrasyon**
  **Dosya:** yeni `Calorisor/Health/HealthKitManager.swift`, `Calorisor/Info.plist`, `Calorisor.entitlements`, `project.yml`, SettingsView (`ContentView.swift`)
  **Talimat:** Okuma: ağırlık, boy, aktif enerji, adım (doğum tarihi/cinsiyet YALNIZ hedef hesabında kullanılacaksa iste — §20.1). Yazma (açık izinle): dietaryEnergy, protein, karbonhidrat, yağ. Info.plist açıklamaları TR/EN. İzin reddinde uygulama normal çalışır. HealthKit verisi proxy'ye/loglara/analitiğe ASLA gitmez (§20.3).
  **Kabul:** §20.5'in tamamı; izin reddi testte crash üretmez.

- [ ] **SF-1502 · Aktif enerji görünümü + kilo trendi**
  **Dosya:** `DailyView.swift`, yeni kilo geçmişi view'ı
  **Kabul:** Günlük ekranda aktif enerji özeti; kilo trend ekranı HealthKit verisiyle.

- [ ] **SF-1503 · HealthKit yazma senkronu (duplicate/düzenleme/silme)**
  **Dosya:** `HealthKitManager.swift`, öğün kayıt/düzenleme akışları
  **Talimat:** Öğün kaydında yaz; düzenlemede eski HealthKit örneğini güncelle/yeniden oluştur; silmede ilişkili kaydı kaldır; duplicate kontrolü (§20.4).
  **Kabul:** Yaz-düzenle-sil zinciri testte tutarlı.

- [ ] **SF-1504 · Haftalık özet hesaplayıcı + Free temel istatistik ekranı**
  **Dosya:** yeni `Calorisor/Models/WeeklySummaryBuilder.swift`, yeni haftalık görünüm
  **Talimat:** §21.2 metrikleri tamamen cihazda hesaplanır (kayıtlı gün, ort. kalori/protein, hedef tutturulan gün, en yüksek/düşük gün, gece öğünü, önceki haftaya değişim; varsa aktif enerji + kilo değişimi). Free kullanıcı bu ekranı görür (AI raporu Pro — §21.5).
  **Kabul:** Builder birim testleri; AI erişimi olmadan ekran çalışır.

- [ ] **SF-1505 · Haftalık AI raporu (Pro)**
  **Dosya:** yeni `proxy/api/weekly-report.ts` (veya scan.ts'e mode), `AIProxyClient.swift`, rapor view'ı
  **Talimat:** Sunucuya YALNIZ §21.3 özet JSON'u gider (ham öğün geçmişi ve ham HealthKit verisi ASLA). Prompt kuralları §21.4: teşhis/tıbbi tavsiye/garanti yok, 1–2 uygulanabilir öneri, utandırmayan dil. Aynı hafta cache'lenir (`calorisor:weekly:{hash}:{week}`); kullanıcı yeniden oluşturabilir; başarısızlıkta SF-1504 ekranı ayakta kalır. "AI tarafından üretildi" ibaresi gösterilir. Rapor istekleri de usage/maliyet loguna girer.
  **Kabul:** §21.6'nın tamamı.

---

## Test planı eşleştirmesi (kaynak §27)

- Proxy senaryoları → `proxy/api/scan.test.ts` (SF-1204'te kurulan vitest; limit/cache/tier/hata/maliyet senaryolarının tamamı).
- iOS senaryoları → mevcut `CalorisorTests/` düzenine yeni dosyalar: InstallationIdentityTests, FreeScanCounterTests (yeniden), AIProxyRequestTests (genişletme), FrequentMealsBuilderTests, WeeklySummaryBuilderTests, HealthKit izin akışı testleri.
- Derleme/test komutları ROADMAP.md §0'daki gibi (`xcodegen generate` → `xcodebuild test -scheme Sofra ...`); yeni .swift dosyalarında `xcodegen generate` unutulmaz.

## Definition of Done

Kaynak dokümanın 28. bölümü aynen geçerlidir; FAZ 11 + SF-1110 manuel işleri tamamlanmadan yayın yapılmaz. FAZ 12–13 yayın sonrası ilk sprint, FAZ 14–15 sonraki iki ürün güncellemesidir (§26 sırası korunur).
