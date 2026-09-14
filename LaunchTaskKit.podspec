Pod::Spec.new do |s|
  pod_macro_flags = '$(inherited) -load-plugin-executable ${PODS_TARGET_SRCROOT}/Prebuilt/LaunchTaskKitMacros#LaunchTaskKitMacros -enable-experimental-feature SymbolLinkageMarkers'
  user_macro_flags = '$(inherited) -load-plugin-executable ${PODS_ROOT}/LaunchTaskKit/Prebuilt/LaunchTaskKitMacros#LaunchTaskKitMacros -enable-experimental-feature SymbolLinkageMarkers'

  s.name = 'LaunchTaskKit'
  s.version = '0.0.1'
  s.summary = 'A lightweight iOS launch task scheduler with macro registration'
  s.homepage = 'https://github.com/FeliksLv01/LaunchTaskKit'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = { 'FeliksLv01' => 'felikslv@163.com' }
  s.source = { :git => 'https://github.com/FeliksLv01/LaunchTaskKit.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/LaunchTaskKit/**/*.swift'
  s.preserve_paths = 'Prebuilt/LaunchTaskKitMacros'
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => pod_macro_flags
  }
  s.user_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => user_macro_flags
  }

  s.test_spec 'Tests' do |ts|
    ts.source_files = 'Tests/LaunchTaskKitTests/**/*.swift'
    ts.pod_target_xcconfig = {
      'OTHER_SWIFT_FLAGS' => pod_macro_flags
    }
    ts.user_target_xcconfig = {
      'OTHER_SWIFT_FLAGS' => user_macro_flags
    }
  end
end
