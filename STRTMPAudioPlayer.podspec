Pod::Spec.new do |s|
  s.name     = "STRTMPAudioPlayer"
  s.version  = "1.0"
  s.summary  = "STRTMPAudioPlayer"
  s.homepage = "https://github.com/saiten/STRTMPAudioPlayer"
  s.author = { "saiten" => "saiten@isidesystem.net" }
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.platform = :ios, '6.0'
  s.requires_arc = true
  s.source_files = "STRTMPAudioPlayer/**/*.{h,m}"
  s.source = { :git => "https://github.com/saiten/STRTMPAudioPlayer.git", :submodules => true }

  s.dependency "TPCircularBuffer"
  
  s.preserve_paths = 'Submodules/**'
  s.libraries = 'crypto', 'ssl', 'rtmp'
  s.vendored_libraries = 'Submodules/OpenSSL-for-iPhone/lib/libcrypto.a', 'Submodules/OpenSSL-for-iPhone/lib/libssl.a', 'Submodules/ios-librtmp/lib/librtmp.a'
  s.xcconfig = { 'HEADER_SEARCH_PATHS' => '$(SRCROOT)/Submodules/OpenSSL-for-iPhone/include $(SRCROOT)/Submodules/ios-librtmp/include' }
end
