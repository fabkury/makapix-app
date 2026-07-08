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
  s.platform         = :ios, '12.0'
  s.requires_arc     = true
end
