#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutoryx_uploader.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutoryx_uploader'
  s.version          = '1.0.0'
  s.summary          = 'Production-grade chunked background uploader for Flutter.'
  s.description      = <<-DESC
A production-grade Flutter plugin for resumable, chunked, background-safe file uploads with real-time speed tracking and ETA estimation.
                       DESC
  s.homepage         = 'https://github.com/SPG-9900/flutoryx_uploader'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'SPG-9900' => 'https://github.com/SPG-9900' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutoryx_uploader_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
