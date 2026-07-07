# Sofra — Design Tokens (Yumuşak Sofra / Soft Native)

Bu doküman `design-tokens.json`'daki değerlerin gerekçesini ve SwiftUI'a geçiş notlarını taşır. Agent'a prompt yazarken bu iki dosya birlikte referans alınmalı.

## Renk mantığı

Sıcak bej zemin (`bg-page`) + tek aksan renk (bakır, `accent-fill`) + nötr metin skalası. Neomorphism'in klasik hatası olan düşük kontrastı önlemek için iki ayrı kural var:

1. **Metin her zaman yüksek kontrastlı skaladan gelir** (`text-primary` / `text-secondary`), asla yumuşak yüzey rengiyle karışmaz.
2. **`accent-fill` (#B87333) metin rengi olarak kullanılmaz** — bg-page üzerinde ~3.36:1 kontrast veriyor, 4.5:1 eşiğinin altında. Vurgulu metin/rakam gerekiyorsa (örn. "86g protein") `accent-text` (#8F5423, ~5.4:1) kullanılır. `accent-fill` sadece buton dolgusu, ikon rengi, halka/grafik gibi metin-olmayan yerlerde kalır.

Her iki mod için de bu ayrım JSON'daki `contrast_notes` alanında not edildi — agent'a "hangi rengi nerede kullanma" kısıtı olarak aynen geçirilebilir.

## Tipografi

**Geist Sans** (UI metni) + **Geist Mono** (sayısal veri — kalori, gram, yüzde). Klişe önerileri bilerek eledim: Inter/Roboto/SF Pro-taklit fontlar "her AI app'i gibi" hissi verir, süslü serif'ler ("Ottoman" hissi) hedef kitleye samimiyetsiz/turistik gelebilir. Geist ikisinin arasında — geometrik ama soğuk değil, native Apple hissini bozmuyor.

Neden mono sadece sayılarda: günlük halka, makro grafikleri gibi yerlerde rakamların hizalanması (tabular figures) önemli — kullanıcı "1.240" ile "980"i yan yana gördüğünde basamaklar kaymamalı. Bu aynı zamanda "Teknik Zarafet" yönünden (4. konsept) ödünç alınan tek unsur — sıcak/organik zemin + hassas/analitik sayı tipografisi kontrastı, ürüne hem sıcaklık hem ciddiyet katıyor.

Fallback: Geist proje ayarlarında embed edilmezse SF Pro / SF Mono'ya düşer (sistem fontu, ek risk yok).

## SwiftUI'a geçiş — hızlı referans

```swift
extension Color {
    init(hex: String) { /* standart hex initializer */ }
}

// Renkler — Assets.xcassets içinde Color Set olarak tanımlanmalı (light/dark otomatik)
Color("bgPage")       // #F4F1EC / #1E1B16
Color("surfaceRaised") // #EDE8DE / #29241D
Color("accentFill")    // #B87333 / #E0A164
Color("textPrimary")   // #3A342A / #F2ECE0
Color("textSecondary") // #6E6659 / #A79C8C  — sadece bu, accent değil

// Raised (kabartma) yüzey — neomorphism çift gölge
.background(Color("surfaceRaised"))
.cornerRadius(24)
.shadow(color: Color("borderHighlight").opacity(0.9), radius: 5, x: -3, y: -3)
.shadow(color: Color("borderShadow").opacity(0.6), radius: 5, x: 3, y: 3)

// Sayısal görüntü (kalori halkası merkezi)
Text("1.240")
    .font(.custom("GeistMono-Medium", size: 36))
    .monospacedDigit()
```

## Spacing / Radius

4px temel birim, ölçek: 4-8-12-16-20-24-32. Radius kademeli: kontroller 12px, standart kartlar 16px, "kabartma" konteynerler (halka arkaplanı, ana kart) 24px — neomorphism'in yumuşaklığı büyük radius ile daha inandırıcı duruyor, 8-12px'te sertleşiyor.

## Motion

`mikro-etkilesimler.md` dosyasındaki her tetikleyici bu dosyadaki `motion` bloğundaki `dur-*` ve `spring` değerlerini kullanır — iki dosya birbirini tamamlıyor, agent prompt'una ikisi birlikte verilecek.
