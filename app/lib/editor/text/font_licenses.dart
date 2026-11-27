// The bundled Text tool fonts on the app's licenses page (About → Licenses): the VEXED pixel
// fonts (CC BY 4.0, which asks for credit and a note of changes), Fusion Pixel Font with the
// fonts it combines, and the CJK library fonts (mostly SIL OFL 1.1, which asks for the license
// text to ship with the font; each text also says what was changed).
// The texts are assets written by tools/fonts/build_fonts.py.
// l10n-ignore-file: font names are proper nouns; license texts are shown as written.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'pixel_font.dart';

bool _registered = false;

/// Add the font licenses to Flutter's [LicenseRegistry]. Idempotent; the assets are read only
/// when the licenses page is opened.
void registerPixelFontLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    const dir = '${PixelFontLibrary.assetDir}/licenses';
    for (final (name, file) in const [
      ('VEXED pixel fonts', 'vexed.txt'),
      ('Fusion Pixel Font', 'fusion_pixel.txt'),
      ('Shinonome, Ayu and Kappa bitmap fonts', 'jfdot.txt'),
      ('KH Dot fonts', 'khdot.txt'),
      ('k8x12', 'k8x12.txt'),
      ('x12y12pxMaruMinya', 'maruminya.txt'),
      ('ChangBanDianSong, RenOuFangSong, QiuYeYuanTi, ShanWeiZhouHei', 'yzdnn.txt'),
      ('RoundPix 12 (ZLabs RoundPix 12px)', 'zlabs.txt'),
      ('BoutiqueBitmap9x9, FashionBitmap16', 'boutique.txt'),
      ('Galmuri', 'galmuri.txt'),
      ('Dunggeun 16 (NeoDunggeunmo)', 'neodgm.txt'),
    ]) {
      try {
        yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString('$dir/$file'));
      } catch (_) {
        // A build without the font assets simply lists no font license.
      }
    }
  });
}
