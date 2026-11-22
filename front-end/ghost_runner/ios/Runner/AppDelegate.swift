import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_soloud leaves the audio session to the app. The default (SoloAmbient) is muted by the
    // silent switch and stops when the screen locks; playback keeps the ghost audible (pairs with
    // UIBackgroundModes `audio`), and mixWithOthers lets the runner's music keep playing.
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
