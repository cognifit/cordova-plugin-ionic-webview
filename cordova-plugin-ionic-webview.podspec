Pod::Spec.new do |s|
  s.name             = 'cognifit-cordova-plugin-ionic-webview'
  s.version          = '5.0.0'
  s.summary          = 'The Web View plugin for Cordova that is specialized for Ionic apps.\n\nThis project use WKWebView (IOS) and some improvements for Webview (Android)'
  s.description      = <<-DESC
The Web View plugin for Cordova that is specialized for Ionic apps.\n\nThis project use WKWebView (IOS) and some improvements for Webview (Android)
                       DESC

  s.homepage         = 'https://github.com/cognifit/cordova-plugin-ionic-webview'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'pgutierrezcf' => 'p.gutierrez@cognifit.com' }
  s.source           = { :git => 'https://github.com/cognifit/cordova-plugin-ionic-webview.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'

  s.source_files = 'src/ios/**/*'
end
