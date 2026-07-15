# Görsel Analiz Modeli Araştırması — Maliyet & Doğruluk (Temmuz 2026)

## Akademik bulgular (Nutrition5k ve benzeri benchmark'lar)

Birden fazla 2025-2026 çalışması şu tabloyu çiziyor:

- **GPT-4o / GPT-4.1 ailesi ve Gemini 2.5 Flash**, yemek tanımada (occlusion/örtüşme dahil) Qwen QVQ-Max ve Claude Sonnet 4'ten belirgin şekilde daha güçlü çıkıyor.
- **Gemini 2.5 Flash, kütle/hacim/enerji tahmininde GPT-4o'ya göre hafif üstün** (enerji tahmini ortalama hata: Gemini %18.2 vs GPT-4o %18.7 — referans nesne varken; referans yokken de benzer küçük fark).
- **Kritik risk:** Bir çalışmada Gemini, hacim/kütle tahmini görevini **zaman zaman reddetti** (muhtemelen güvenlik/temkinlilik davranışı) — bu yüzden o araştırma ekibi üretim workflow'unda GPT'yi tercih etti, sadece doğruluk yüzünden değil, **güvenilirlik/kesinlik** yüzünden. **Bu risk production'da kabul edilemez — free kullanıcının 3 hakkından biri Gemini refusal yüzünden yanmasın.**
- **Qwen-VL ailesi** (QVQ-Max, Qwen2.5-VL, Qwen3-VL) genel tanımada zayıf kalıyor, özellikle **örtüşen/karışık tabaklarda** (occlusion >%80'de doğruluk ~%60'a düşüyor) — bu doğrudan bizim "calp" ve ev yemeği (güveç, mercimek çorbası gibi tek renkli/karışık dokulu yemekler) senaryomuz için risk.
- Latency: GPT-4.1 mini en hızlı (~5-6sn), Qwen-VL-Max en yavaş (>15sn), Gemini 2.5 Flash orta ama daha uzun/detaylı yanıt üretme eğiliminde (token maliyetini artırıyor).

## Maliyet karşılaştırması (Temmuz 2026 güncel fiyatları)

### OpenAI (vision-capable modeller)

Fiyatlar 1M token başına USD. Sütunlar: normal input / cached input / output.
(Önceki sürümde başlıklar yanlıştı — "output" sütunu aslında cached input,
"blended" sütunu ise gerçek output fiyatıydı. Aşağıdaki tablo düzeltilmiştir.)

| Model | Input | Cached input | Output | Vision |
|-------|-------|--------------|--------|--------|
| **GPT-4.1 mini** | $0.40 | $0.10 | $1.60 | ✅ En hızlı, güvenilir |
| **GPT-4.1 nano** | $0.10 | $0.025 | $0.40 | ✅ En ucuz OpenAI |
| GPT-5-mini | $0.25 | $0.025 | $2.00 | ✅ |
| GPT-5-nano | $0.05 | $0.005 | $0.40 | ✅ |
| GPT-5.4-mini | $0.75 | $0.075 | $4.50 | ✅ Gereğinden güçlü |
| GPT-4o | $2.50 | $1.25 | $10.00 | ✅ |
| GPT-4o-mini | $0.15 | $0.075 | $0.60 | ✅ |

### Google (Gemini)

| Model | Input | Output | Vision |
|-------|-------|--------|--------|
| Gemini 2.5 Flash-Lite | $0.10 | ~$0.40 | ✅ Reddetme riski var |
| Gemini 3.1 Flash-Lite | $0.25 | $1.50 | ✅ |

### Tarama başına maliyet — neden tek bir sabit sayı vermiyoruz

> **Eski ve hatalı hesap (kaldırıldı):** Önceki sürümdeki "~$0.000026 (nano) /
> ~$0.00013 (mini) tarama başı" değerleri yanlıştı. O hesap, output tokenları
> yanlışlıkla cached-input fiyatıyla (nano $0.005, mini $0.025) çarpıyordu;
> gerçek output fiyatı nano $0.40, mini $2.00'dır — yani eski rakamlar
> gerçeğin ~4 katı altındaydı. Ayrıca `detail: high` görselin ~500 tokenden
> daha fazla token tükettiğini hesaba katmıyordu. Bu sayılara güvenmeyin.

Tek bir sabit "tarama başı maliyet" vermek yanıltıcıdır çünkü maliyet şunlara
göre değişir:

- **Görsel çözünürlüğü / oranı** — daha büyük veya daha uzun kenarlı görseller
  daha çok tile → daha çok input token.
- **`detail` seviyesi** — `high` (bizim seçtiğimiz) öngörülebilir ama `low`'dan
  daha çok token kullanır; `auto` zamanla değişebilir.
- **Prompt uzunluğu** — locale'e göre değişen sistem/temel prompt.
- **JSON Schema (Structured Outputs)** — şema da input tokenlarına dâhildir.
- **Completion tokenları** — modelin ürettiği JSON'un uzunluğu (kaç yemek, kaç
  alan).
- **Reasoning tokenları** — `reasoning_effort` (`low`/`minimal`) completion
  içinde faturalanır; ikinci kez ücretlendirilmez.
- **OpenAI prompt cache** — tekrar eden prompt önekleri cached-input fiyatına
  düşer (nano $0.005, mini $0.025 / 1M).
- **Calp Redis cache** — aynı normalize girdi 7 gün içinde tekrar gelirse
  OpenAI hiç çağrılmaz; o taramanın maliyeti $0'dır.

**Canlı sistemde gerçek maliyet, tahminle değil, OpenAI `usage` cevabından
hesaplanır** (`proxy/lib/openai-cost.ts` → `calculatedCostMicrousd`). Normal ve
cached input ayrı fiyatlandırılır, output ayrı; günlük toplam ve model bazlı
kırılım günlük raporda (`proxy/scripts/daily-report.ts`) görülür.

**Sonuç (model seçimi):** GPT-5-mini, Gemini 2.5 Flash-Lite ile benzer fiyat
sınıfındadır ama daha yeni ve refusal riski yoktur. GPT-5-nano ise en ucuz
seçenektir. Mutlak maliyeti günlük rapordan takip edin.

## Tavsiye (güncellendi — Temmuz 2026)

**Birincil model (pro): GPT-5-mini** — input $0.25 / cached $0.025 / output $2.00 (1M), GPT-5 ailesi (en yeni jenerasyon), GPT-4.1 mini'den hem daha ucuz hem daha yeni. Görsel tanıma kalitesi GPT-4.1 mini ile en az eşdeğer, muhtemelen daha iyi.

**Free model: GPT-5-nano** — input $0.05 / cached $0.005 / output $0.40 (1M), GPT-5 ailesinin en ucuz üyesi, aynı davranış profili. Free tarama maliyeti düşüktür ama sabit değildir; gerçek değer OpenAI `usage`'dan hesaplanır (yukarı bkz.).

**Gemini artık kullanılmıyor.** Refusal riski production'da kabul edilemez. GPT-5 ailesi hem daha ucuz hem daha güvenilir.

## Tier-based model routing (Phase 4)

Client, her istekte `tier` alanını gönderir (`"free"` veya `"pro"`). Değer `FreeScanCounter.shared.isSubscribed` (StoreKit 2) üzerinden belirlenir.

| Tier | Primary | Fallback | Fiyat (1M: input / cached / output) |
|------|---------|----------|-------------------------------------|
| **free** | GPT-5-nano | Yok | $0.05 / $0.005 / $0.40 |
| **pro** | GPT-5-mini | GPT-5-nano | $0.25 / $0.025 / $2.00 |

Tarama başı sabit maliyet vermiyoruz (yukarıdaki "neden" bölümüne bakın);
gerçek maliyet OpenAI `usage`'dan hesaplanır.

**Neden böyle?**
- GPT-5-mini: GPT-5 ailesi (en yeni), input $0.25 / output $2.00, GPT-4.1 mini'den daha yeni jenerasyon
- GPT-5-nano: input $0.05 / output $0.40 — en ucuz üye. Aynı aile, tutarlı davranış
- İkisi de OpenAI GPT-5 ailesi → aynı token formatı, aynı API, cross-provider sorunu yok
- Free'de fallback yok (3 tarama, GPT-5-nano'nun hata oranı ihmal edilebilir)
- Pro'da GPT-5-mini primary, hata alırsa GPT-5-nano'ya düşer

**Backend'in yapması gereken:** `tier` alanına göre:
- `"free"` → GPT-5-nano çağrısı, hata durumunda direkt hata dön
- `"pro"` → GPT-5-mini dene, hata alırsan GPT-5-nano'ya geç, o da başarısız olursa hata dön

Client model-agnostic — sadece `tier` gönderir, backend dilediği zaman model değiştirebilir.
