import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 펼친 iPhone Duo 판정용(lib/core/utils/foldable_layout.dart).
    // Flutter 는 iOS 에서 기기 idiom 도, 접힘선(displayFeatures)도 주지 않아
    // 화면 크기만으로는 펼친 Duo 와 iPad 를 가를 수 없다.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceIdiom") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "seoul_subway/device", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "isPhoneIdiom" {
        result(UIDevice.current.userInterfaceIdiom == .phone)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
