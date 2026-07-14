# Calorisor · Gerçek Cihaz QA & Yayın Kapısı

Bu liste SF-1008 kapsamında Fatih'in iPhone'unda doldurulacak.
Her adımı gerçek cihazda gözlemledikten sonra ✅ veya ❌ ile işaretle.
❌ için kısa gözlem yaz ve ROADMAP'e yeni görev ekle.

- Tarih: —
- Cihaz / iOS: —
- Uygulama sürümü / build: 1.0.0 (1)
- Backend: demo / Vercel (kullanılanı yaz)

---

## Tam Tur — TR (cihaz dili Türkçe)

### Onboarding
- [ ] Onboarding açılıyor, 7 adım sırayla ilerliyor (Hedef → Boy → Kilo → Aktivite → Yaş → Cinsiyet → Sonuç)
- [ ] Tüm metinler Türkçe, Goal/ActivityLevel display name'ler Türkçe
- [ ] Hedef ekranında hesaplanan kalori ve makrolar gösteriliyor
- [ ] "Nasıl hesapladık?" disclosure group çalışıyor
- [ ] Medical disclaimer görünüyor

### Paywall
- [ ] Paywall "Calorisor Pro" başlığıyla açılıyor
- [ ] Fiyat ve plan seçimi doğru (aylık/yıllık, 7 gün ücretsiz deneme)
- [ ] "3 ücretsiz tarama ile devam et" ile kapanıyor
- [ ] "Satın Alımları Geri Yükle" ve "Abonelik Yönetimi" butonları var
- [ ] Gizlilik Politikası / Kullanım Koşulları linkleri tıklanabilir
- [ ] Otomatik yenileme metni doğru

### Bugün (Daily)
- [ ] Selamlama (Günaydın/İyi günler/İyi akşamlar) ve tarih doğru
- [ ] Capture bar görünüyor — kamera ve yazı butonları tıklanabilir
- [ ] Kalori halkası doğru değeri gösteriyor, tıklayınca remaining/consumed/target arası geçiş yapıyor
- [ ] Makro kartları (Protein/Karb./Yağ) doğru değerlerle görünüyor
- [ ] Hızlı ekleme sayaçları çalışıyor — tıklayınca artıyor, eksi ile azalıyor
- [ ] 7 günlük özet kartı ve sparkline var
- [ ] Boş durumda "Bugün henüz öğün eklemedin" ve Lottie/ikon fallback görünüyor
- [ ] "Elle gir" butonu manual entry sheet açıyor

### Elle Ekle (Manual Entry)
- [ ] Sheet açılıyor, form görünüyor
- [ ] Kalori zorunlu, makrolar opsiyonel
- [ ] "Ekle" butonu sadece kalori > 0 ise aktif
- [ ] Kaydedince Bugün'e ekleniyor, halka güncelleniyor

### Kamera
- [ ] Kamera izni isteniyor (ilk açılışta)
- [ ] Kamera kartı düzgün görünüyor (3:4 aspect, corner brackets)
- [ ] Flaş aç/kapat çalışıyor
- [ ] Tap-to-focus çalışıyor
- [ ] Fotoğraf çekme çalışıyor (shutter flash + haptik)
- [ ] Galeri'den fotoğraf seçme çalışıyor
- [ ] İzin reddedilince "Kamera izni gerekli" ekranı ve "Ayarlar'ı Aç" butonu
- [ ] Free scan badge doğru sayıyı gösteriyor

### Analiz
- [ ] Analiz overlay açılıyor, fotoğraf arkada görünüyor
- [ ] Corner brackets + dönen başlık ("Tabak inceleniyor…" → "Porsiyonlar ölçülüyor…" → "Kaloriler hesaplanıyor…")
- [ ] 3-segment progress düzgün çalışıyor
- [ ] Tanınan öğeler sırayla reveal oluyor (stagger)
- [ ] Hata kartları düzgün görünüyor (rate-limit, offline, server error)

### Sonuç (Result)
- [ ] Sonuç ekranı tanınan öğelerle açılıyor
- [ ] Her öğe için: isim, birim, miktar, kalori, makrolar
- [ ] İsim düzenleme (tap-to-edit) çalışıyor
- [ ] Birim değiştirme (horizontal scroll picker) çalışıyor
- [ ] Miktar +/- stepper çalışıyor
- [ ] Silme (xmark) çalışıyor
- [ ] Bottom bar canlı toplamları gösteriyor (kcal, protein, karb, yağ)
- [ ] "Logla" butonu çalışıyor, Bugün'e dönüyor
- [ ] Düzenleme yapıldıysa çıkışta "Düzenlemeler kaydedilmedi" uyarısı

### Yazarak Ekle (TextLog)
- [ ] Açılıyor, metin alanı ve öneri chip'leri görünüyor
- [ ] Türkçe öneriler: çay, simit, mercimek çorbası, ekmek, yoğurt, ayran, yumurta, salata
- [ ] Öneri chip'ine tıklayınca metin alanına ekleniyor
- [ ] "Analiz Et" butonu boş metinde inaktif
- [ ] Analiz çalışıyor, sonuç ekranına yönlendiriyor

### Geçmiş (History)
- [ ] Aylara göre gruplanmış gün listesi
- [ ] 7 günlük özet kartı (embedded)
- [ ] Gün satırı: renkli dot (yeşil=hedef altı, gri=hedef üstü), gün adı, tarih, kcal, öğün sayısı
- [ ] Gün detayına tıklayınca DayDetailView açılıyor
- [ ] DayDetailView: kalori halkası, makro kartı, ÖĞÜNLER ve HIZLI EKLEMELER listesi
- [ ] Boş durumda "Henüz kayıtlı gün yok" mesajı

### Ayarlar (Settings)
- [ ] Abonelik durumu doğru (Pro/Aktif veya kalan tarama sayısı)
- [ ] Günlük hedefler (kalori, protein, karb, yağ) stepper ile değiştirilebiliyor
- [ ] "Kaloriden makro dağıt" butonu çalışıyor
- [ ] Profil: Hedef, Aktivite, Boy, Kilo, Yaş, Biyolojik cinsiyet değiştirilebiliyor
- [ ] Profil değişince "hedefler yeniden hesaplansın mı?" dialog'u
- [ ] Dil seçici: Sistem / Türkçe / English
- [ ] "Tüm Verilerimi Sil" → onay dialog'u → silme → onboarding'e dönüş
- [ ] "Verilerimi Dışa Aktar" → CSV → Share Sheet
- [ ] "Geri Bildirim Gönder" → mailto: açılıyor
- [ ] Gizlilik Politikası / Kullanım Koşulları linkleri

### Widget
- [ ] Ana ekran widget'ı (small) kalori halkasını gösteriyor
- [ ] Ana ekran widget'ı (medium) halka + makroları gösteriyor
- [ ] Kilit ekranı widget'ı (circular) progress ring gösteriyor
- [ ] Kilit ekranı widget'ı (inline) "X kcal kaldı" gösteriyor
- [ ] Widget'a tıklayınca uygulama Bugün sekmesinde açılıyor

---

## Tam Tur — EN (cihaz dili İngilizce veya in-app EN seçili)

### Onboarding
- [ ] Tüm başlıklar ve alt metinler İngilizce
- [ ] Goal: "Lose weight", "Maintain", "Gain weight", "Build muscle"
- [ ] Activity: "Sedentary", "Lightly active", "Moderately active", "Very active", "Extremely active"
- [ ] "Your Daily Target" → "calories/day" → "Continue" → "How did we calculate this?"
- [ ] Medical disclaimer İngilizce

### Paywall
- [ ] "Calorisor Pro", plan seçimi, özellik kartı İngilizce
- [ ] Feature rows: "Unlimited photo calorie tracking", "Unlimited text meal logging", "Smarter AI", "First access to new Pro features"

### Bugün (Today)
- [ ] Greeting: "Good morning" / "Good afternoon" / "Good evening"
- [ ] Capture bar: "Snap your plate, see its calories"
- [ ] Section headers: "MACROS", "THIS WEEK", "TODAY'S MEALS"
- [ ] Quick-add template picker: Bread, Coffee, Water, Egg, Banana… (İngilizce isimler)
- [ ] Empty state: "You haven't logged any meals today"

### Yazarak Ekle (TextLog)
- [ ] Öneriler İngilizce: coffee, bread slice, yogurt, eggs, salad, apple, banana, milk
- [ ] "WHAT DID YOU EAT?" ve "QUICK ADD" başlıkları

### Kamera / Analiz / Sonuç
- [ ] Kamera başlığı: "Scan Your Plate"
- [ ] Analiz durumu: "Inspecting plate…", "Measuring portions…", "Calculating calories…"
- [ ] Sonuç: "Results" → "X items recognized"
- [ ] Portion units: ladle, tbsp, glass, tea glass, slice, handful, bowl, piece
- [ ] Hata mesajları İngilizce

### Geçmiş (History) / Ayarlar (Settings)
- [ ] "History" / "ALL DAYS" / "No recorded days yet"
- [ ] "Settings" → tüm bölüm başlıkları ve etiketler İngilizce
- [ ] Data deletion dialog İngilizce
- [ ] Language picker shows "System" / "Turkish" / "English"

### Widget
- [ ] Widget metinleri İngilizce ("left", "kcal left")

---

## Erişilebilirlik (VoiceOver)

- [ ] Kamera: tüm ikon butonlar okunuyor (Kapat, Flaş, Fotoğraf çek, Galeri, Yazarak ekle)
- [ ] Analiz: Vazgeç butonu okunuyor, arka plan fotoğrafı atlanıyor
- [ ] Sonuç: Kapat butonu okunuyor, küçük resim atlanıyor, Azalt/Artır butonları okunuyor
- [ ] Bugün: capture bar butonları okunuyor, boş durum Lottie animasyonu atlanıyor
- [ ] Kalori halkası: tıklanabilir olduğu ve güncel değeri okunuyor
- [ ] Onboarding slider'ları: güncel değer okunuyor (örn. "170 cm", "70 kg", "30")
- [ ] QuickCounter: Ekle, Azalt, Artır butonları okunuyor
- [ ] Ayarlar stepper'ları: hedef adı okunuyor (örn. "Günlük kalori")
- [ ] Geçmiş: chevron okları atlanıyor

## Görsel (Light/Dark · Dynamic Type · Küçük Ekran)

- [ ] Light mode: tüm ekranlar okunabilir, kontrast yeterli
- [ ] Dark mode: tüm ekranlar okunabilir, renk token'ları doğru
- [ ] Dynamic Type (en büyük ayar): metinler taşmıyor, scroll çalışıyor
- [ ] Dynamic Type (en büyük ayar): buton ikonları ve frame'ler kırılmıyor
- [ ] iPhone SE (veya simülatör): Paywall tek ekranda sığıyor (ViewThatFits)
- [ ] iPhone SE: yedi günlük özet sütunları taşmıyor
- [ ] Gerçek cihaz: app icon maskesi doğru (köşeler kırpılmamış, şekil doğru)

---

## Yayın Kapısı (Fatih Aksiyon)

- [ ] `calorisor.app` alan adı kayıtlı
- [ ] Privacy Policy sayfası yayında (`https://calorisor.app/privacy`)
- [ ] Terms of Use sayfası yayında (`https://calorisor.app/terms`)
- [ ] App Store Connect'te "Calorisor" ismi rezerve edildi
- [ ] TURKPATENT marka araştırması tamam (sınıf 9, 42)
- [ ] USPTO / EUIPO marka araştırması tamam
- [ ] Foodvisor isim benzerliği hukuki değerlendirmesi yapıldı
- [ ] Sosyal medya kullanıcı adı (@calorisor) kontrol edildi
- [ ] `AIProxyEndpointURL` gerçek Vercel deployment URL'si ile değiştirildi
- [ ] `AIProxyAPIKey` gerçek `CALORISOR_CLIENT_KEY` ile değiştirildi
- [ ] `DEVELOPMENT_TEAM` project.yml'da ayarlandı
- [ ] App Store Connect: aylık ve yıllık ürünler oluşturuldu
- [ ] App Store Connect: yıllık planda 7 günlük introductory offer tanımlandı
- [ ] App Store Connect: privacy nutrition label dolduruldu
- [ ] App Store ekran görüntüleri (TR + EN, tüm ekran boyutları) hazır
- [ ] App Store açıklaması ve anahtar kelimeler (TR + EN) hazır
- [ ] Destek e-postası (`destek@calorisor.app`) aktif

---

## Bulgular

Kritik hata yoksa: `Kritik ❌ yok.`
