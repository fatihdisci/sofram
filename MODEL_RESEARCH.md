# Görsel Analiz Modeli Araştırması — Maliyet & Doğruluk (Temmuz 2026)

## Akademik bulgular (Nutrition5k ve benzeri benchmark'lar)

Birden fazla 2025-2026 çalışması şu tabloyu çiziyor:

- **GPT-4o / GPT-4.1 ailesi ve Gemini 2.5 Flash**, yemek tanımada (occlusion/örtüşme dahil) Qwen QVQ-Max ve Claude Sonnet 4'ten belirgin şekilde daha güçlü çıkıyor.
- **Gemini 2.5 Flash, kütle/hacim/enerji tahmininde GPT-4o'ya göre hafif üstün** (enerji tahmini ortalama hata: Gemini %18.2 vs GPT-4o %18.7 — referans nesne varken; referans yokken de benzer küçük fark).
- **Kritik risk:** Bir çalışmada Gemini, hacim/kütle tahmini görevini **zaman zaman reddetti** (muhtemelen güvenlik/temkinlilik davranışı) — bu yüzden o araştırma ekibi üretim workflow'unda GPT'yi tercih etti, sadece doğruluk yüzünden değil, **güvenilirlik/kesinlik** yüzünden.
- **Qwen-VL ailesi** (QVQ-Max, Qwen2.5-VL, Qwen3-VL) genel tanımada zayıf kalıyor, özellikle **örtüşen/karışık tabaklarda** (occlusion >%80'de doğruluk ~%60'a düşüyor) — bu doğrudan bizim "sofra" ve ev yemeği (güveç, mercimek çorbası gibi tek renkli/karışık dokulu yemekler) senaryomuz için risk. Tek avantajı: Doğu Asya mutfağında hafif üstünlük — bizim için ilgisiz.
- Latency: GPT-4.1 mini en hızlı (~5-6sn), Qwen-VL-Max en yavaş (>15sn — bizim "3 saniyede sonuç" hedefiyle çelişir), Gemini 2.5 Flash orta ama daha uzun/detaylı yanıt üretme eğiliminde (token maliyetini artırıyor).

## Maliyet karşılaştırması (Temmuz 2026 fiyatları)

| Model | Input | Output | Görsel özel not |
|---|---|---|---|
| **Gemini 2.5 Flash-Lite** | $0.10/1M token | ~$0.40/1M token | En ucuz, kanıtlanmış, mevcut Arvia zincirinde zaten kullanılıyor |
| **Gemini 3.1 Flash-Lite** | $0.25/1M token | $1.50/1M token | Biraz daha yeni/güçlü, hâlâ ucuz |
| **GPT-4.1 mini** | $0.40/1M token | $1.60/1M token | En hızlı yanıt, sağlam görsel tanıma |
| **GPT-5.4 mini** | $0.75/1M token | $4.50/1M token | Daha güçlü ama gereğinden pahalı bu görev için |
| **Qwen-VL-Plus / Qwen2.5-VL** (OpenRouter) | ~$0.14-0.33/1M token | ~$0.41-1.3/1M token | Ucuz ama occlusion zayıflığı + yavaş — MVP için önerilmez |

Bir taramanın gerçek maliyeti (görsel + kısa prompt + JSON çıktı, ~500-1000 token toplam) her seçenekte de **$0.0005-0.002 bandında** kalıyor — yani hangisini seçersen seç, orijinal rapordaki "200-300 abone bile kârlı" hesabı bozulmuyor. Asıl karar kriteri maliyet değil, **güvenilirlik ve hız**.

## Tavsiye

**Birincil model: Gemini 2.5 Flash-Lite (veya 3.1 Flash-Lite)** — doğruluk/hacim tahmininde hafif üstün, en ucuz, Arvia'daki mevcut zincirle tutarlı.

**Otomatik yedek: GPT-4.1 mini** — Gemini'nin reddettiği (hacim/kütle tahmini) veya hata döndürdüğü durumlarda devreye girer. Bu zaten Phase 1 prompt'undaki "model-agnostic client" mimarisiyle bire bir örtüşüyor — proxy, Gemini'den reddetme/hata sinyali alırsa GPT-4.1 mini'ye otomatik geçiş yapacak şekilde tasarlanmalı.

**Qwen-VL ailesi MVP'de kullanılmıyor** — occlusion zayıflığı bizim ana kullanım senaryomuzla (karışık/örtüşen ev yemeği tabakları) doğrudan çelişiyor. İleride, kendi RTX 3060'ında self-host edilebilir bir deney/maliyet-sıfırlama seçeneği olarak nota düşülüyor ama şimdilik plan dışı.

## Tier-based model routing (Phase 3d/4)

Client, her istekte `tier` alanını gönderir (`"free"` veya `"pro"`). Değer `FreeScanCounter.shared.isSubscribed` (StoreKit 2) üzerinden belirlenir.

| Tier | Primary Model | Fallback | Tahmini maliyet/tarama |
|------|--------------|----------|----------------------|
| **free** | Gemini 2.5 Flash-Lite | Yok (hata dönerse kullanıcıya "tekrar dene") | ~$0.0003-0.0008 |
| **pro** | Gemini 2.5 Flash-Lite | GPT-4.1 mini (auto-fallback) | ~$0.0005-0.002 |

**Free tier neden fallback'siz?** Maliyet optimizasyonu. Free kullanıcı ömür boyu sadece 3 tarama yapabilir — 3 taramanın birinde hata olsa bile kullanıcı "tekrar dene" ile düzeltebilir. Fallback zinciri sadece sınırsız tarama yapan pro kullanıcılar için anlamlı.

**Backend'in yapması gereken:** `tier` alanına göre:
- `"free"` → sadece Gemini 2.5 Flash-Lite çağrısı, hata durumunda direkt hata dön
- `"pro"` → Gemini 2.5 Flash-Lite dene, refusal/error alırsan GPT-4.1 mini'ye geç, o da başarısız olursa hata dön

Bu tavsiye `PHASE_1_PROMPT.md`'deki "AI proxy networking client" bölümüne bir **fallback chain** olarak yansıtıldı (aşağıya bakınız).
