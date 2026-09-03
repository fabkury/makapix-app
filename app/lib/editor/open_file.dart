// File → Open (CONTEXT.md "Open" vs "Import"): what the picker accepts, how a picked file is told
// apart, and the one refusal rule. Pure Dart so the rules are testable without the engine; the
// flow itself lives in editor_page.fileio.dart (`_open`, `_openMkpx`, `_openRaster`).
//
// Open brings a WHOLE file in as a new drawing, true to the source: an `.mkpx` with everything
// intact, a raster file at its own size with one frame per animation frame. It never scales,
// crops, or places — that is Import, into the current drawing. A raster larger than the canvas
// cap therefore cannot Open and is refused toward Import (2026-09-03).

/// Raster formats Open accepts — the same set the Import picker offers.
const List<String> kOpenImageExtensions = ['png', 'gif', 'apng', 'webp', 'jpg', 'jpeg', 'bmp'];

/// Everything the Open picker lists: `.mkpx` first, then the raster formats.
const List<String> kOpenExtensions = ['mkpx', ...kOpenImageExtensions];

/// The two `.mkpx` signatures (format spec §4.1 plain, §16 compact): `0x89 M K P X|Z 0D 0A 1A`.
/// The picked file is sniffed by these, never trusted by extension — Android pickers ignore the
/// filter and files get renamed — so a mislabeled document still Opens as a document and a
/// mislabeled image still Opens as an image.
bool isMkpxBytes(List<int> bytes) {
  if (bytes.length < 8) return false;
  return bytes[0] == 0x89 &&
      bytes[1] == 0x4D && // M
      bytes[2] == 0x4B && // K
      bytes[3] == 0x50 && // P
      (bytes[4] == 0x58 || bytes[4] == 0x5A) && // X plain · Z compact
      bytes[5] == 0x0D &&
      bytes[6] == 0x0A &&
      bytes[7] == 0x1A;
}

/// The drawing title for an opened file: the file name without its extension (any of the
/// accepted ones, case-insensitive). An unknown or missing extension leaves the name as is.
String titleFromFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  final ext = name.substring(dot + 1).toLowerCase();
  return kOpenExtensions.contains(ext) ? name.substring(0, dot) : name;
}

/// The lowercased extension recorded as the imported format (provenance), or `image` when the
/// name carries none.
String importedFormatFromFileName(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 || dot == name.length - 1 ? 'image' : name.substring(dot + 1).toLowerCase();
}

/// Why a `w`×`h` raster cannot Open (a side over [maxDim] — the canvas cap), as the message to
/// show, or `null` when it can. Import is the gesture that scales or crops, so the message
/// points there.
String? openRasterRefusal(int w, int h, {required int maxDim}) {
  if (w >= 1 && h >= 1 && w <= maxDim && h <= maxDim) return null;
  if (w < 1 || h < 1) return "This image is empty and can't be opened.";
  return '$w×$h is larger than the $maxDim×$maxDim maximum. Use Import image… to scale or crop it.';
}
