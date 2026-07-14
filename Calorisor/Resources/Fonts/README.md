# Geist fonts — drop-in slot

Phase 1 ships with the typography scale wired to `.system(...)` fallbacks (SF Pro / SF
Mono) so nothing is blocked on sourcing font files. To switch to **Geist** (the intended
UI + numeric typeface), do three things:

1. **Add the font files here** (`Sofra/Resources/Fonts/`). Cover the weights the scale uses:
   - `Geist-Regular`, `Geist-Medium`, `Geist-SemiBold` (Sans)
   - `GeistMono-Regular`, `GeistMono-Medium` (Mono)
   Static `.otf`/`.ttf` files are simplest. (Geist is MIT-licensed, from Vercel.)

2. **Register them in `Info.plist`** by adding a `UIAppFonts` array listing each filename, e.g.:
   ```xml
   <key>UIAppFonts</key>
   <array>
       <string>Geist-Regular.otf</string>
       <string>Geist-Medium.otf</string>
       <string>Geist-SemiBold.otf</string>
       <string>GeistMono-Regular.otf</string>
       <string>GeistMono-Medium.otf</string>
   </array>
   ```
   (Also make sure the files are members of the Sofra target so they get bundled. With
   XcodeGen they're picked up automatically once present here; re-run `xcodegen generate`.)

3. **Flip the flag**: set `SofraTypography.geistAvailable = true` in
   `Sofra/DesignSystem/Font+Tokens.swift`.

Verify the exact PostScript names of the files you add match `geistSansName` /
`geistMonoName` in `Font+Tokens.swift` (use Font Book → right-click → "Show in Finder"
or `mdls -name com_apple_ats_name_postscript <file>`), and adjust if a vendor names a
weight differently.
