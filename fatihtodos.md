# Calorisor — Fatih'in Yayın Öncesi Yapılacakları

> Bu liste yalnızca bilgisayar, Apple/Vercel/Upstash/App Store hesapları ve gerçek
> cihaz gerektiren işleri içerir. Kod tarafındaki tamamlanan maddeler `ROADMAP.md`de
> tutulur. Her adımı gözlemledikten sonra `[x]` yap; bir sorun görürsen kısa notunu
> `PHASE_QA_NOTES.md`ye yaz.

## Mevcut teknik durum

- Aktif dal: `main`
- Proje: `Calorisor.xcodeproj`
- Uygulama bundle ID: `com.fatih.calorisor`
- Widget bundle ID: `com.fatih.calorisor.widget`
- Apple Team: `8XPP7Z37GF`
- iOS minimum sürümü: 17.0
- Kod tarafında hazır: sesli giriş, Siri/Kestirmeler ile taslak yemek ekleme,
  yerel öğün hatırlatmaları, manuel giriş, TR/EN dil seçimi ve widget.
- Son doğrulama: uygulama + widget, aynı Apple Development sertifikasıyla imzalı
  iOS build'de başarıyla derlendi.

---

## 1. Başlangıç — doğru projeyi aç

- [x] Terminalde güncel kodu al:

  ```bash
  cd /Users/fatihdisci/apps/sofram
  git switch main
  git pull --ff-only origin main
  open Calorisor.xcodeproj
  ```

- [x] Xcode üst çubuğunda scheme olarak **Calorisor**, hedef olarak kendi iPhone'un seçili.
- [x] `Signing & Capabilities` altında hem **Calorisor** hem de
  **CalorisorWidgetExtension** için aynı Team seçili: `8XPP7Z37GF`.
- [x] Her iki target için `Automatically manage signing` açık.
- [x] `Cmd + R` ile telefona kur ve uygulamayı aç.

> Not: `xcodegen generate` çalıştırman gerekirse Team ayarı artık `project.yml`de
> kayıtlı. Generate sonrası `Calorisor.xcodeproj` değişikliğini de commit et.

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
  - `CALORISOR_CLIENT_KEY`
  - `UPSTASH_REDIS_REST_URL`
  - `UPSTASH_REDIS_REST_TOKEN`
- [x] Production deploy tamamlanınca adresi al:
  `https://sofram-five.vercel.app/api/scan`
- [x] Yerelde [Calorisor/Info.plist](/Users/fatihdisci/apps/sofram/Calorisor/Info.plist:67) içindeki
  `AIProxyEndpointURL` ve `AIProxyAPIKey` değerlerini güncelle. OpenAI API anahtarını
  iOS uygulamasına asla koyma ve bu iki gerçek değeri Git'e commit etme.
- [x] `proxy/README.md`deki text-mode smoke testini canlı endpoint'e karşı çalıştır;
  JSON analiz yanıtının döndüğünü doğrula.
- [ ] Aynı text-mode isteğini `-i` ile iki kez çalıştır; ilk çağrıda
  `x-calorisor-cache: miss`, tekrar çağrıda `hit` olduğunu doğrula.

## 2.1 Yeni backend güncellemesi — installation hash + günlük limitler (FAZ 11)

> `claude/oku-tch6nr` dalındaki proxy değişiklikleri (SF-1103/1104) canlıya
> alınırken gerekli. Kod hazır; bunlar yalnız Vercel/OpenAI panelinde yapılır.

- [ ] **Vercel env — ZORUNLU, deploy'dan ÖNCE:** `INSTALLATION_HASH_SALT` ekle
  (güçlü rastgele değer: `openssl rand -hex 32`). Eklenmezse endpoint tüm
  isteklere **502** döner (kasıtlı güvenlik davranışı, uygulama hatası değil).
- [ ] Deploy sonrası smoke testte yeni yanıt header'larını doğrula:
  `x-calorisor-tier`, `x-calorisor-photo-remaining/-limit`,
  `x-calorisor-text-remaining/-limit` (`curl -i` ile görünür).
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
- [ ] `https://calorisor.app/privacy` ve `/terms` sayfalarını gerçek veri akışıyla güncelle: installation hash, 7 günlük cache, token/maliyet kaydı, AI sonuçlarının tahmin olduğu ve adil kullanım.
- [ ] App Store Privacy Nutrition Label'ı proxy'nin 7 günlük cache davranışıyla tutarlı doldur; “hiç veri toplanmıyor” seçme.

## 3. Gerçek cihazda önce yeni özellikleri test et

- [x] **Sesli giriş:** Bugün → yazı ile ekle → mikrofon. Mikrofon ve Konuşma Tanıma
  izinlerini ver; Türkçe bir öğün söyle; canlı transkripti düzelt; `Analiz Et` →
  sonuç → `Kaydet` akışını tamamla.
- [x] Sonuç ekranında porsiyon/ad düzenleme; kayıttan sonra Bugün ve Geçmiş ekranında
  öğeye dokunarak ad, porsiyon ve gerekirse makroları düzenleme akışını doğrula.
- [ ] İzinleri reddedip tekrar dene; açıklayıcı hata ve `Ayarlar'ı Aç` seçeneği görünmeli,
  yazılı giriş çalışmaya devam etmeli.
- [ ] **Siri/Kestirmeler:** Kestirmeler'de Calorisor eylemini bul ya da Siri'ye
  “Calorisor'a yemek ekle” de. Metin uygulamaya taslak olarak gelmeli; sen onaylamadan
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

- [ ] Subscription Group: **Calorisor Pro**.
- [ ] Ürünler aynı grupta:
  - `com.fatih.calorisor.monthly`
  - `com.fatih.calorisor.annual`
- [ ] Aylık plan için deneme ekleme.
- [ ] Yıllık plan için Introductory Offer: **Free / 1 Week** (= 7 gün).
- [ ] Her ürün için TR ve EN görünen ad, açıklama, fiyat, review screenshot ve notları ekle.
- [ ] Sandbox hesabıyla satın alma, geri yükleme ve yıllık deneme metnini gerçek cihazda doğrula.

## 6. Yayın kapısı: marka, hukuk ve gizlilik

- [ ] [CALORISOR_BRAND_CHECK.md](/Users/fatihdisci/apps/sofram/CALORISOR_BRAND_CHECK.md:1)
  içindeki App Store isim, `calorisor.app`, TÜRKPATENT, USPTO/EUIPO ve sosyal medya
  kontrollerini tamamla.
- [ ] `https://calorisor.app/privacy` ve `/terms` sayfalarını gerçek metinle yayına al.
- [ ] Markalı destek e-postasını hazırla.
- [ ] App Store Privacy Nutrition Label'ı `proxy/README.md`deki 7 günlük cache
  davranışıyla tutarlı doldur. “Hiç veri toplanmıyor” seçeneğini seçme.

## 7. App Store materyalleri ve gönderim

- [ ] TR + EN App Store başlığı, alt başlık, açıklama ve anahtar kelimeleri hazırla.
- [ ] Calorisor markasıyla TR ve EN ekran görüntüsü setlerini oluştur.
- [ ] TestFlight build yükle; en az bir gerçek cihazda tekrar test et.
- [ ] App Store Connect'te uygulama, abonelikler, privacy alanları ve review notlarını
  aynı sürümde `Ready for Review` durumuna getir.
- [ ] `PHASE_QA_NOTES.md`de kritik ❌ kalmadığında App Store gönderimi için sürüm/commit kararını ver.

---

## Yapman gerekmeyenler

- Sesli giriş, transkript düzenleme, Siri/Kestirmeler, hatırlatmalar, String Catalog
  ve uygulama/widget signing uyumu kod tarafında hazır.
- OpenAI anahtarını veya Vercel/Upstash gerçek sırlarını repoya yazma.
- Eski **Sofra** proje/target/adlarını kullanma; her yerde marka ve proje adı
  **Calorisor**.
