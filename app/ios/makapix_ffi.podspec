#
# makapix_ffi.podspec — vendors the Rust engine's static xcframework into the Runner target.
#
# The .xcframework is produced by build_ios.sh (run before `flutter build ipa`) and is
# git-ignored, so this pod is only resolvable after that script has run. CocoaPods links
# the static archive into the app binary; the C symbols are then reachable at runtime via
# DynamicLibrary.process() (app/lib/engine_ffi.dart on iOS).
#
Pod::Spec.new do |s|
  s.name             = 'makapix_ffi'
  s.version          = '0.1.0'
  s.summary          = 'Static C-ABI bridge to the Makapix Rust engine (iOS).'
  s.description      = 'Vendors MakapixFFI.xcframework (libmakapix_ffi.a for device + simulator) built by build_ios.sh.'
  s.homepage         = 'https://makapix.club'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Makapix' => 'pub@kury.dev' }
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'MakapixFFI.xcframework'
  s.platform         = :ios, '13.0'
  s.requires_arc     = true
  # Dart resolves the engine's C API at runtime via DynamicLibrary.process(), so NOTHING references
  # these symbols at link time. In release, -dead_strip therefore drops every entry point that isn't
  # explicitly kept (a debug build keeps them only because it doesn't strip). We mark each one as a
  # linker root with `-u`, which keeps its code; `-u` (vs -force_load with an explicit path) is
  # slice-agnostic and doesn't trip Xcode's build-input validation; CocoaPods already links the right
  # slice via -lmakapix_ffi.
  #
  # `-export_dynamic` is ALSO required: keeping the code is not enough — dlsym(RTLD_DEFAULT, …) needs
  # the symbols in the main executable's export trie. Xcode 16-era ld left -u roots exported, and R2
  # was closed on that behavior (Scaleway Mac, 2026-07-08); Xcode 26's linker dead-strips them from
  # the export table even when -u keeps the code, which shipped TestFlight builds whose editor died
  # with "Failed to lookup symbol 'mkpx_new'" (found 2026-07-09, first on-device editor run of a CI
  # build). -export_dynamic preserves global symbols of a main executable through LTO/dead-strip.
  # codemagic.yaml carries a post-build gate that fails the build if the exports go missing again.
  #
  # The symbol set is derived from the built archive at pod-install time so it can never drift from
  # the actual FFI surface. build_ios.sh must have produced the xcframework first.
  _ffi_lib  = File.join(__dir__, 'MakapixFFI.xcframework', 'ios-arm64', 'libmakapix_ffi.a')
  _ffi_syms = `nm -gU "#{_ffi_lib}" 2>/dev/null`.scan(/(_mkpx_\w+)/).flatten.uniq
  raise "makapix_ffi.podspec: no _mkpx_* symbols in #{_ffi_lib} — run ./build_ios.sh first" if _ffi_syms.empty?
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => (['-Wl,-export_dynamic'] + _ffi_syms.map { |sym| "-Wl,-u,#{sym}" }).join(' ')
  }
end
