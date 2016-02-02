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
  s.libraries = "z"
  s.vendored_libraries = "Submodules/ios-librtmp/lib/librtmp.a"
  
  s.preserve_paths = 'STRTMPAudioPlayer/*.pch', 'Submodules/**'
  s.prefix_header_file = 'STRTMPAudioPlayer/STRTMPAudioPlayer-Prefix.pch'
  s.xcconfig = {
    "HEADER_SEARCH_PATHS" => "Submodules/ios-librtmp/include"
  }
end
