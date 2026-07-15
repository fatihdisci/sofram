# Calp — Fatih'in Yayın Öncesi Yapılacakları

> Bu liste yalnızca bilgisayar, Apple/Vercel/Upstash/App Store hesapları ve gerçek
> cihaz gerektiren işleri içerir. Kod tarafındaki tamamlanan maddeler `ROADMAP.md`de
> tutulur. Her adımı gözlemledikten sonra `[x]` yap; bir sorun görürsen kısa notunu
> `PHASE_QA_NOTES.md`ye yaz.

## Mevcut teknik durum

- Aktif dal: `main`
- Proje: `Calp.xcodeproj`
- Uygulama bundle ID: `com.fatih.calp`
- Widget bundle ID: `com.fatih.calp.widget`
- Apple Team: `8XPP7Z37GF`
- iOS minimum sürümü: 17.0
- Kod tarafında hazır: sesli giriş, Siri/Kestirmeler ile taslak yemek ekleme,
  yerel öğün hatırlatmaları, manuel giriş, TR/EN dil seçimi ve widget.
- Son doğrulama: uygulama + widget, aynı Apple Development sertifikasıyla imzalı
  iOS build'de başarıyla derlendi.

---

## 0. Eski marka → Calp yeniden markalama — Apple Developer / App Store Connect (ZORUNLU) <!-- brand-keep -->

> Kod tarafındaki tüm yeniden adlandırma tamamlandı ve doğrulandı (build + 132 test
> + widget + proxy testleri geçti). Aşağıdakiler yalnızca Apple hesabında elle
> yapılır. Bundle ID değiştiği için Apple açısından **yeni bir uygulama kimliğidir**;
> uygulama henüz yayımlanmadığından tam geçiş uygundur.

- [ ] **App ID `com.fatih.calp`** oluştur (Certificates, Identifiers & Profiles →
  Identifiers). Capability'ler: **HealthKit**, **Push Notifications**,
  **App Groups**, **iCloud (CloudKit)**.
- [ ] **App ID `com.fatih.calp.widget`** oluştur. Capability: **App Groups**.
- [ ] **App Group `group.com.fatih.calp`** oluştur ve her iki App ID'ye bağla.
- [ ] **iCloud container `iCloud.com.fatih.calp`** oluştur ve ana App ID'ye bağla.
- [ ] Xcode'da `Automatically manage signing` açık; Team `8XPP7Z37GF`. Yeni bundle
  ID'lerle provisioning profilleri otomatik yeniden üretilir (elle profil gerekmez).
- [ ] **App Store Connect'te yeni uygulama kaydı**: `com.fatih.calp`.
  (Not: rename öncesi otomatik oluşan `com.fatih.calorisor` kaydı — App ID 6791274030 — artık kullanılmıyor; silebilir/bırakabilirsin.) <!-- brand-keep -->
- [ ] **StoreKit ürünleri (Senaryo A — eski ürünler ASC'de hiç oluşturulmadı):**
  yeni Subscription Group **Calp Pro** + `com.fatih.calp.monthly` /
  `com.fatih.calp.annual` (ayrıntı: bölüm 5). Yeni kullanıcı arayüzü yalnız Calp
  ürünlerini gösterir; kodda eski `com.fatih.calorisor.*` ID'leri yalnız proxy legacy-allowlist'inde. <!-- brand-keep -->
- [ ] **Vercel env:** `CALP_CLIENT_KEY` (ve varsa `CALP_DAILY_COST_ALERT_MICROUSD`) ekle.
  Eski `CALORISOR_*` env'ler geçiş fallback'i; canlı doğrulama sonrası kaldırılabilir. <!-- brand-keep -->
- [ ] **Domain:** `calp.app` sahipliğini doğrula/al — kod artık `https://calp.app/privacy`
  ve `/terms`'e işaret ediyor. Domain hazır olana kadar bu linkler çalışmaz.
- [ ] **Vercel endpoint** `https://sofram-five.vercel.app/api/scan` çalışmaya devam
  ediyor; yeniden markalama için değiştirmeye gerek yok (istenirse ileride
  `api.calp.app`'e taşınabilir).

## 1. Başlangıç — doğru projeyi aç

- [x] Terminalde güncel kodu al:

  ```bash
  cd /Users/fatihdisci/apps/sofram
  git switch main
  git pull --ff-only origin main
  open Calp.xcodeproj
  ```

- [x] Xcode üst çubuğunda scheme olarak **Calp**, hedef olarak kendi iPhone'un seçili.
- [x] `Signing & Capabilities` altında hem **Calp** hem de
  **CalpWidgetExtension** için aynı Team seçili: `8XPP7Z37GF`.
- [x] Her iki target için `Automatically manage signing` açık.
- [x] `Cmd + R` ile telefona kur ve uygulamayı aç.

> Not: `xcodegen generate` çalıştırman gerekirse Team ayarı artık `project.yml`de
> kayıtlı. Generate sonrası `Calp.xcodeproj` değişikliğini de commit et.

## 2. Proxy'yi canlıya al

- [x] Upstash'te Redis veritabanı oluştur ve şunları kaydet:
  - `UPSTASH_REDIS_REST_URL`
  - `UPSTASH_REDIS_REST_TOKEN`
- [x] Güçlü istemci anahtarı üret:

  ```bash
  openssl rand -hex 32
  ```

- [x] Vercel'de GitHub'daki `sofram` reposunu içe aktar; **Root Directory**: `proxy`.
- [x] Vercel Environment Variables'a şunları ekle:
  - `OPENAI_API_KEY`
  - `CALP_CLIENT_KEY`
  - `UPSTASH_REDIS_REST_URL`
  - `UPSTASH_REDIS_REST_TOKEN`
- [x] Production deploy tamamlanınca adresi al:
  `https://sofram-five.vercel.app/api/scan`
- [x] Yerelde [Calp/Info.plist](/Users/fatihdisci/apps/sofram/Calp/Info.plist:67) içindeki
  `AIProxyEndpointURL` ve `AIProxyAPIKey` değerlerini güncelle. OpenAI API anahtarını
  iOS uygulamasına asla koyma ve bu iki gerçek değeri Git'e commit etme.
- [x] `proxy/README.md`deki text-mode smoke testini canlı endpoint'e karşı çalıştır;
  JSON analiz yanıtının döndüğünü doğrula.
- [ ] Aynı text-mode isteğini `-i` ile iki kez çalıştır; ilk çağrıda
  `x-calp-cache: miss`, tekrar çağrıda `hit` olduğunu doğrula.

## 2.1 Yeni backend güncellemesi — installation hash + günlük limitler (FAZ 11)

> `claude/oku-tch6nr` dalındaki proxy değişiklikleri (SF-1103/1104) canlıya
> alınırken gerekli. Kod hazır; bunlar yalnız Vercel/OpenAI panelinde yapılır.

- [ ] **Vercel env — ZORUNLU, deploy'dan ÖNCE:** `INSTALLATION_HASH_SALT` ekle
  (güçlü rastgele değer: `openssl rand -hex 32`). Eklenmezse endpoint tüm
  isteklere **502** döner (kasıtlı güvenlik davranışı, uygulama hatası değil).
- [ ] Deploy sonrası smoke testte yeni yanıt header'larını doğrula:
  `x-calp-tier`, `x-calp-photo-remaining/-limit`,
  `x-calp-text-remaining/-limit` (`curl -i` ile görünür).
- [ ] Free hesapta aynı gün **2. fotoğraf** analizinin `daily_limit_reached`
  (429) döndüğünü; **3. metin/ses** isteğinin de limitlendiğini gözle. Ses
  girişi metin havuzunu tüketir (1 yazılı + 1 sesli = 3. istek bloke).
- [ ] (Opsiyonel, sonra) Tüm kullanıcılar installation header'ı gönderen sürüme
  geçtiğinde Vercel'e `REQUIRE_INSTALLATION_ID=true` ekle; header'sız istekler
  400 alsın (o ana kadar IP-hash fallback'i devrede).
- [ ] (Öneri — maliyet güvenliği, §22.3) OpenAI'da ayrı project aç; hard/soft
  bütçe ve günlük harcama alarmı kur. AI anahtarını yalnız bu proxy'de kullan.

## 2.2 SF-1110 — yayın öncesi manuel işler

- [ ] App Store Connect'te TR lansman fiyatlarını doğrula: aylık 129,99 TL / yıllık 799,99 TL.
- [ ] Sonraki TR fiyatlarını planla: aylık 149,99 TL / yıllık 899,99 TL; haftalık ürün ekleme.
- [ ] Global fiyatları doğrula: aylık 6,99 USD / yıllık 29,99 USD.
- [ ] Yalnız yıllık üründe Free / 1 Week introductory offer bırak; aylık üründe deneme olmadığını doğrula.
- [ ] Her iki üründe Family Sharing'i App Store Connect'te aç.
- [ ] App Store açıklaması ve ekran görüntülerinde “sınırsız AI” vaadi kullanma; günlük yüksek limitli analiz kopyasını kullan.
- [ ] Vercel Production env'e `INSTALLATION_HASH_SALT` eklemeden deploy etme; ardından yeni quota header'larıyla smoke test yap.
- [ ] OpenAI için ayrı project aç; hard/soft bütçe ve günlük harcama alarmı kur; anahtarı yalnız Vercel'de tut.
- [ ] `https://calp.app/privacy` ve `/terms` sayfalarını gerçek veri akışıyla güncelle: installation hash, 7 günlük cache, token/maliyet kaydı, AI sonuçlarının tahmin olduğu ve adil kullanım.
- [ ] App Store Privacy Nutrition Label'ı proxy'nin 7 günlük cache davranışıyla tutarlı doldur; “hiç veri toplanmıyor” seçme.

## 3. Gerçek cihazda önce yeni özellikleri test et

- [x] **Sesli giriş:** Bugün → yazı ile ekle → mikrofon. Mikrofon ve Konuşma Tanıma
  izinlerini ver; Türkçe bir öğün söyle; canlı transkripti düzelt; `Analiz Et` →
  sonuç → `Kaydet` akışını tamamla.
- [x] Sonuç ekranında porsiyon/ad düzenleme; kayıttan sonra Bugün ve Geçmiş ekranında
  öğeye dokunarak ad, porsiyon ve gerekirse makroları düzenleme akışını doğrula.
- [ ] İzinleri reddedip tekrar dene; açıklayıcı hata ve `Ayarlar'ı Aç` seçeneği görünmeli,
  yazılı giriş çalışmaya devam etmeli.
- [ ] **Siri/Kestirmeler:** Kestirmeler'de Calp eylemini bul ya da Siri'ye
  “Calp'e yemek ekle” de. Metin uygulamaya taslak olarak gelmeli; sen onaylamadan
  geçmişe kayıt düşmemeli.
- [ ] **Bildirimler:** Ayarlar → Bildirimler bölümünde bir öğün hatırlatmasını açıp
  saati birkaç dakika ileri kur. Bildirime dokununca Bugün ekranı açılmalı.
- [ ] Aynı alanda `Hiç kayıt yok` ve `Gece özeti` tercihlerini ayrı ayrı dene;
  `Tüm bildirimleri kapat` bekleyen bildirimleri temizlemeli.

## 4. Ana uygulama QA turu

- [ ] `PHASE_QA_NOTES.md`deki **TR** turunu gerçek cihazda baştan sona doldur.
- [ ] Uygulama dilini English yapıp **EN** turunu doldur.
- [ ] Kamera izni, fotoğraf tarama, hata/offline durumu, manuel giriş, quick-add,
  geçmiş, CSV export, veri silme ve widget'ları test et.
- [ ] Dynamic Type'ın en büyük ayarında, Light/Dark modda ve küçük ekranlı iPhone'da
  kritik ekranlara bak.
- [ ] Bir hata bulursan `PHASE_QA_NOTES.md`ye ❌ ve kısa gözlem yaz; ardından
  `ROADMAP.md`ye net bir geliştirme maddesi ekle.

## 5. Abonelikleri App Store Connect'te kur

- [ ] Subscription Group: **Calp Pro**.
- [ ] Ürünler aynı grupta:
  - `com.fatih.calp.monthly`
  - `com.fatih.calp.annual`
- [ ] Aylık plan için deneme ekleme.
- [ ] Yıllık plan için Introductory Offer: **Free / 1 Week** (= 7 gün).
- [ ] Her ürün için TR ve EN görünen ad, açıklama, fiyat, review screenshot ve notları ekle.
- [ ] Sandbox hesabıyla satın alma, geri yükleme ve yıllık deneme metnini gerçek cihazda doğrula.

## 6. Yayın kapısı: marka, hukuk ve gizlilik

- [ ] [CALP_BRAND_CHECK.md](/Users/fatihdisci/apps/sofram/CALP_BRAND_CHECK.md:1)
  içindeki App Store isim, `calp.app`, TÜRKPATENT, USPTO/EUIPO ve sosyal medya
  kontrollerini tamamla.
- [ ] `https://calp.app/privacy` ve `/terms` sayfalarını gerçek metinle yayına al.
- [ ] Markalı destek e-postasını hazırla.
- [ ] App Store Privacy Nutrition Label'ı `proxy/README.md`deki 7 günlük cache
  davranışıyla tutarlı doldur. “Hiç veri toplanmıyor” seçeneğini seçme.

## 7. App Store materyalleri ve gönderim

- [ ] TR + EN App Store başlığı, alt başlık, açıklama ve anahtar kelimeleri hazırla.
- [ ] Calp markasıyla TR ve EN ekran görüntüsü setlerini oluştur.
- [ ] TestFlight build yükle; en az bir gerçek cihazda tekrar test et.
- [ ] App Store Connect'te uygulama, abonelikler, privacy alanları ve review notlarını
  aynı sürümde `Ready for Review` durumuna getir.
- [ ] `PHASE_QA_NOTES.md`de kritik ❌ kalmadığında App Store gönderimi için sürüm/commit kararını ver.

---

## Yapman gerekmeyenler

- Sesli giriş, transkript düzenleme, Siri/Kestirmeler, hatırlatmalar, String Catalog
  ve uygulama/widget signing uyumu kod tarafında hazır.
- OpenAI anahtarını veya Vercel/Upstash gerçek sırlarını repoya yazma.
- Rename öncesi eski proje/target/adlarını kullanma; her yerde marka ve proje adı
  **Calp**.
