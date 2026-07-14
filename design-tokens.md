# Calorisor — Design Tokens

Calorisor, beslenme için bir “dashboard” değil; tabağı hızlıca anlamaya yarayan karakterli bir araçtır. Görsel dil, Arc/Search'ın doğrudanlığına yakın: düz yüzeyler, güçlü tipografi, az ama kasıtlı renk.

## Kesin kurallar

- Gradient, glassmorphism, kabartı, iç/dış gölge ve sahte fiziksel derinlik yok.
- Zeminler düz kırık beyaz veya near-black; kartlar yalnız dolgu, boşluk ve 1pt sınırla ayrılır.
- Tek marka vurgusu Calorisor kırmızısıdır. Vurgu rengi yalnız dolgu/ikon/grafik içindir; uzun metin için kullanılmaz.
- Geist Sans arayüz ve başlıklarda, Geist Mono tüm kalori/gram/yüzde ölçümlerinde kullanılır.
- App icon'daki kırık `C`, küçük bir imza olarak kullanılır; dekoratif tekrar eden motif değildir.

## Renk ve yüzey hiyerarşisi

`bgPage` uygulama zemini; `surfaceRaised` birincil düz kart; `surfaceFlat` ikincil giriş/filtre alanıdır. `raisedSurface` ve `pressedSurface` isimleri uyumluluk için kalır, ancak gölge üretmez: her ikisi de düz dolgu ve `borderHairline` kullanır.

`accentFill` düz Calorisor kırmızısıdır. Onun üzerinde yalnız `onAccent` kullanılır. Metin her zaman `textPrimary`, `textSecondary` veya `textMuted` ölçeğinden gelir.

## Spacing, radius ve motion

4px temel ölçek korunur: 4 / 8 / 12 / 16 / 20 / 24 / 32. Radius kontrollerde 12, kartlarda 16'dır; geniş 24pt radius yalnız gerçek bir ana blok gerektiğinde kullanılır. Motion kısa ve işlevsel kalır; veri kaydı/analiz sonucunu destekler, arayüzü süslemez.
