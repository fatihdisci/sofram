# Görsel Analiz Modeli Araştırması — Maliyet & Doğruluk (Temmuz 2026)

## Akademik bulgular (Nutrition5k ve benzeri benchmark'lar)

Birden fazla 2025-2026 çalışması şu tabloyu çiziyor:

- **GPT-4o / GPT-4.1 ailesi ve Gemini 2.5 Flash**, yemek tanımada (occlusion/örtüşme dahil) Qwen QVQ-Max ve Claude Sonnet 4'ten belirgin şekilde daha güçlü çıkıyor.
- **Gemini 2.5 Flash, kütle/hacim/enerji tahmininde GPT-4o'ya göre hafif üstün** (enerji tahmini ortalama hata: Gemini %18.2 vs GPT-4o %18.7 — referans nesne varken; referans yokken de benzer küçük fark).
- **Kritik risk:** Bir çalışmada Gemini, hacim/kütle tahmini görevini **zaman zaman reddetti** (muhtemelen güvenlik/temkinlilik davranışı) — bu yüzden o araştırma ekibi üretim workflow'unda GPT'yi tercih etti, sadece doğruluk yüzünden değil, **güvenilirlik/kesinlik** yüzünden. **Bu risk production'da kabul edilemez — free kullanıcının 3 hakkından biri Gemini refusal yüzünden yanmasın.**
- **Qwen-VL ailesi** (QVQ-Max, Qwen2.5-VL, Qwen3-VL) genel tanımada zayıf kalıyor, özellikle **örtüşen/karışık tabaklarda** (occlusion >%80'de doğruluk ~%60'a düşüyor) — bu doğrudan bizim "sofra" ve ev yemeği (güveç, mercimek çorbası gibi tek renkli/karışık dokulu yemekler) senaryomuz için risk.
- Latency: GPT-4.1 mini en hızlı (~5-6sn), Qwen-VL-Max en yavaş (>15sn), Gemini 2.5 Flash orta ama daha uzun/detaylı yanıt üretme eğiliminde (token maliyetini artırıyor).

## Maliyet karşılaştırması (Temmuz 2026 güncel fiyatları)

### OpenAI (vision-capable modeller)

| Model | Input | Output | Blended | Vision |
|-------|-------|--------|---------|--------|
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

### Tarama başına gerçek maliyet

Bir tarama = görsel (~500 input token) + kısa prompt + JSON çıktı (~200 output token):

| Model | Maliyet/tarama | 100 tarama/gün (aylık) |
|-------|---------------|----------------------|
| **GPT-5-nano** ★ free | **~$0.000026** | ~$0.08 |
| **GPT-5-mini** ★ pro | **~$0.00013** | ~$0.39 |
| GPT-5.4-mini | ~$0.00039 | ~$1.17 |
| GPT-4.1 mini | ~$0.00022 | ~$0.66 |
| GPT-4.1 nano | ~$0.000055 | ~$0.17 |
| GPT-4o-mini | ~$0.00009 | ~$0.27 |
| Gemini 2.5 Flash-Lite | ~$0.00013 | ~$0.39 |

**Sonuç:** GPT-5-mini, Gemini 2.5 Flash-Lite ile aynı fiyata geliyor ama daha yeni ve refusal riski yok. GPT-5-nano ise neredeyse bedava.

## Tavsiye (güncellendi — Temmuz 2026)

**Birincil model (pro): GPT-5-mini** — $0.25/$0.025, GPT-5 ailesi (en yeni jenerasyon), GPT-4.1 mini'den hem daha ucuz hem daha yeni. Görsel tanıma kalitesi GPT-4.1 mini ile en az eşdeğer, muhtemelen daha iyi.

**Free model: GPT-5-nano** — $0.05/$0.005, ultra ucuz (~$0.000026/tarama). 3 free taramanın toplam maliyeti ~$0.00008 — yani bedava. GPT-5 ailesinden, aynı davranış profili.

**Gemini artık kullanılmıyor.** Refusal riski production'da kabul edilemez. GPT-5 ailesi hem daha ucuz hem daha güvenilir.

## Tier-based model routing (Phase 4)

Client, her istekte `tier` alanını gönderir (`"free"` veya `"pro"`). Değer `FreeScanCounter.shared.isSubscribed` (StoreKit 2) üzerinden belirlenir.

| Tier | Primary | Fallback | Maliyet/tarama |
|------|---------|----------|---------------|
| **free** | GPT-5-nano | Yok | ~$0.000026 |
| **pro** | GPT-5-mini | GPT-5-nano | ~$0.00013 |

**Neden böyle?**
- GPT-5-mini: GPT-5 ailesi (en yeni), $0.25/$0.025, GPT-4.1 mini'den %40 daha ucuz ve daha yeni jenerasyon
- GPT-5-nano: $0.05/$0.005 — 3 free tarama toplam ~$0.00008 (bedava). Aynı aile, tutarlı davranış
- İkisi de OpenAI GPT-5 ailesi → aynı token formatı, aynı API, cross-provider sorunu yok
- Free'de fallback yok (3 tarama, GPT-5-nano'nun hata oranı ihmal edilebilir)
- Pro'da GPT-5-mini primary, hata alırsa GPT-5-nano'ya düşer

**Backend'in yapması gereken:** `tier` alanına göre:
- `"free"` → GPT-5-nano çağrısı, hata durumunda direkt hata dön
- `"pro"` → GPT-5-mini dene, hata alırsan GPT-5-nano'ya geç, o da başarısız olursa hata dön

Client model-agnostic — sadece `tier` gönderir, backend dilediği zaman model değiştirebilir.
