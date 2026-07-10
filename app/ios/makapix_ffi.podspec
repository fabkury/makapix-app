#
# makapix_ffi.podspec — vendors the Rust engine's DYNAMIC framework into the Runner app.
#
# The .xcframework is produced by build_ios.sh (run before `flutter build ipa`) and is
# git-ignored, so this pod is only resolvable after that script has run. CocoaPods links
# the framework and embeds+signs it into Runner.app/Frameworks; Dart opens it at runtime
# with DynamicLibrary.open('MakapixFFI.framework/MakapixFFI') (app/lib/engine_ffi.dart).
#
# HISTORY (don't regress this): the engine was originally a STATIC archive reached via
# DynamicLibrary.process(), held alive through -dead_strip by -u linker roots. Xcode 26's
# linker silently stopped honoring -u (and -exported_symbol/-export_dynamic) for the main
# executable — the symbols vanished with no link error and every CI build shipped a dead
# editor (found 2026-07-09, builds #8/#9 diagnostics). A dynamic framework is immune: a
# dylib is its own export table and the app link never strips it. codemagic.yaml carries
# a post-build gate verifying the _mkpx_* exports in the exact .ipa that ships.
#
Pod::Spec.new do |s|
  s.name             = 'makapix_ffi'
  s.version          = '0.1.0'
  s.summary          = 'Dynamic C-ABI bridge to the Makapix Rust engine (iOS).'
  s.description      = 'Vendors MakapixFFI.xcframework (dynamic framework for device + simulator) built by build_ios.sh.'
  s.homepage         = 'https://makapix.club'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Makapix' => 'pub@kury.dev' }
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'MakapixFFI.xcframework'
  s.platform         = :ios, '13.0'
  s.requires_arc     = true

  # Fail pod install loudly if build_ios.sh hasn't produced the framework (or produced an
  # empty one) — a silent absence would only surface as a runtime engine-load error.
  _ffi_bin = File.join(__dir__, 'MakapixFFI.xcframework', 'ios-arm64', 'MakapixFFI.framework', 'MakapixFFI')
  raise "makapix_ffi.podspec: #{_ffi_bin} missing — run ./build_ios.sh first" unless File.exist?(_ffi_bin)
  _ffi_syms = `nm -gU "#{_ffi_bin}" 2>/dev/null`.scan(/(_mkpx_\w+)/).flatten.uniq
  raise "makapix_ffi.podspec: no _mkpx_* symbols exported by #{_ffi_bin}" if _ffi_syms.empty?
end
