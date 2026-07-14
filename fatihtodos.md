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

- [ ] Terminalde güncel kodu al:

  ```bash
  cd /Users/fatihdisci/apps/sofram
  git switch main
  git pull --ff-only origin main
  open Calorisor.xcodeproj
  ```

- [ ] Xcode üst çubuğunda scheme olarak **Calorisor**, hedef olarak kendi iPhone'un seçili.
- [ ] `Signing & Capabilities` altında hem **Calorisor** hem de
  **CalorisorWidgetExtension** için aynı Team seçili: `8XPP7Z37GF`.
- [ ] Her iki target için `Automatically manage signing` açık.
- [ ] `Cmd + R` ile telefona kur ve uygulamayı aç.

> Not: `xcodegen generate` çalıştırman gerekirse Team ayarı artık `project.yml`de
> kayıtlı. Generate sonrası `Calorisor.xcodeproj` değişikliğini de commit et.

## 2. Proxy'yi canlıya al

- [ ] Upstash'te Redis veritabanı oluştur ve şunları kaydet:
  - `UPSTASH_REDIS_REST_URL`
  - `UPSTASH_REDIS_REST_TOKEN`
- [ ] Güçlü istemci anahtarı üret:

  ```bash
  openssl rand -hex 32
  ```

- [ ] Vercel'de GitHub'daki `sofram` reposunu içe aktar; **Root Directory**: `proxy`.
- [ ] Vercel Environment Variables'a şunları ekle:
  - `OPENAI_API_KEY`
  - `CALORISOR_CLIENT_KEY`
  - `UPSTASH_REDIS_REST_URL`
  - `UPSTASH_REDIS_REST_TOKEN`
- [ ] Production deploy tamamlanınca adresi al:
  `https://PROJE-ADI.vercel.app/api/scan`
- [ ] Yerelde [Calorisor/Info.plist](/Users/fatihdisci/apps/sofram/Calorisor/Info.plist:67) içindeki
  `AIProxyEndpointURL` ve `AIProxyAPIKey` değerlerini güncelle. OpenAI API anahtarını
  iOS uygulamasına asla koyma ve bu iki gerçek değeri Git'e commit etme.
- [ ] `proxy/README.md`deki text-mode smoke testini canlı endpoint'e karşı çalıştır.
  İlk çağrı 200 + `x-calorisor-cache: miss`, tekrar çağrı `hit` olmalı.

## 3. Gerçek cihazda önce yeni özellikleri test et

- [ ] **Sesli giriş:** Bugün → yazı ile ekle → mikrofon. Mikrofon ve Konuşma Tanıma
  izinlerini ver; Türkçe bir öğün söyle; canlı transkripti düzelt; `Analiz Et` →
  sonuç → `Kaydet` akışını tamamla.
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
