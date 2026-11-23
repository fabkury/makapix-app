// The bundled Text tool fonts on the app's licenses page (About → Licenses): the VEXED pixel
// fonts (CC BY 4.0, which asks for credit and a note of changes) and Fusion Pixel Font with
// the fonts it combines (SIL OFL 1.1, which asks for the license text to ship with the font).
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
    ]) {
      try {
        yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString('$dir/$file'));
      } catch (_) {
        // A build without the font assets simply lists no font license.
      }
    }
  });
}
