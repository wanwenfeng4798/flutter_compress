#
# Shared iOS + macOS podspec (sharedDarwinSource).
# See https://docs.flutter.dev/packages-and-plugins/developing-packages
#
Pod::Spec.new do |s|
  s.name             = 'flutter_compress_pro'
  s.version          = '0.1.0'
  s.summary          = 'High-quality Flutter video & image compression with precise target-size control.'
  s.description      = <<-DESC
Video compression via AVAssetReader/Writer (iOS & macOS, no FFmpeg).
Image compression via ImageIO with target-size, quality and lossless modes.
                       DESC
  s.homepage         = 'https://github.com/wanwenfeng4798/flutter_compress_pro'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'ck'
  s.source           = { :path => '.' }
  s.source_files = 'flutter_compress_pro/Sources/flutter_compress_pro/**/*.swift'
  s.swift_version = '5.0'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  s.resource_bundles = {
    'flutter_compress_pro_privacy' => ['flutter_compress_pro/Sources/flutter_compress_pro/PrivacyInfo.xcprivacy']
  }
end
