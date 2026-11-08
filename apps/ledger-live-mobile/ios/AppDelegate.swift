import UIKit
import UserNotifications
import ObjectiveC.runtime

import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

import FirebaseCore
import FirebaseMessaging

import BrazeKit
import BrazeUI
import braze_react_native_sdk

import Expo
import ExpoModulesCore
import ExpoSplashScreen

import SharedNativePerformance

@main
class AppDelegate: RCTAppDelegate, UNUserNotificationCenterDelegate {

  private var launchedFromPush = false
  var overlayBlurView: UIVisualEffectView?
  var overlayLogoView: UIImageView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppStartupModule.recordLaunch(application)
    self.moduleName = "ledgerlivemobile"
    self.dependencyProvider = RCTAppDependencyProvider()

    // Increase max concurrent HTTP connections per host (iOS default is 6) to reduce boot-time
    // request queuing. See: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpmaximumconnectionsperhost
    RCTSetCustomNSURLSessionConfigurationProvider {
      let config = URLSessionConfiguration.default
      config.httpMaximumConnectionsPerHost = 16
      if let useWifiOnly = Bundle.main.infoDictionary?["ReactNetworkForceWifiOnly"] as? Bool, useWifiOnly {
        config.allowsCellularAccess = false
      }
      config.httpShouldSetCookies = true
      config.httpCookieAcceptPolicy = .always
      config.httpCookieStorage = HTTPCookieStorage.shared
      return config
    }

    FirebaseConfigurator.configure()

    var pushAutoEnabled = true
    if UserDefaults.standard
      .object(
        forKey: AppKeys.UserDefaults.iOSPushAutoEnabled
      ) != nil {
      pushAutoEnabled = UserDefaults.standard
        .bool(
          forKey: AppKeys.UserDefaults.iOSPushAutoEnabled
        )
    }
    if pushAutoEnabled {
      print(
        "iOS Push Auto enabled."
      )
    }

    UNUserNotificationCenter.current().delegate = self

    BrazeManager.shared.configure(
      pushAutoEnabled: pushAutoEnabled
    )

    if !pushAutoEnabled {
      print(
        "iOS Push Auto disabled - Registering for push manually."
      )
      registerForPushNotifications()
    }

    BrazeReactUtils
      .sharedInstance()
      .populateInitialPayload(
        fromLaunchOptions: launchOptions
      )

    launchedFromPush = launchOptions?[.remoteNotification] != nil

    let appLaunched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if !appLaunched {
        return false
    }

    let isRunningDetox = ProcessInfo.processInfo.arguments.contains(
      "-IS_TEST"
    )
    if isRunningDetox {
      return true
    }

    if let rootView = window.rootViewController?.view {
      SplashScreenManager.shared.initWith(rootView)
    }

    UserDefaults.standard.set(
      false,
      forKey: AppKeys.UserDefaults.biometricInProgressOverlay
    )

    return true
  }

  // MARK: - RCTBridgeDelegate
  override func sourceURL(for bridge: RCTBridge) -> URL? {
    return self.bundleURL()
  }

  override func bundleURL() -> URL? {
    #if DEBUG
      return RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
    #else
      return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
    #endif
  }

  // MARK: - Push registration

  func registerForPushNotifications() {
    let center = UNUserNotificationCenter.current()
    center
      .setNotificationCategories(
        Braze.Notifications.categories
      )
    center.delegate = self
    UIApplication.shared
      .registerForRemoteNotifications()
  }

  // MARK: - Remote notifications


  @objc(application:didRegisterForRemoteNotificationsWithDeviceToken:)
  override dynamic func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken

    BrazeManager.shared.register(deviceToken: deviceToken)
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo

    if launchedFromPush {
      launchedFromPush = false
    } else if let urlString = userInfo["ab_uri"] as? String,
              let url = URL(string: urlString) {
      RCTLinkingManager.application(
        UIApplication.shared,
        open: url,
        options: [:]
      )
    }

    let processedByBraze = BrazeManager.shared.handleUserNotification(
      response: response,
      completion: completionHandler
    )
    if processedByBraze {
      return
    }
    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (
      UNNotificationPresentationOptions
    ) -> Void
  ) {
    if #available(
      iOS 14.0,
      *
    ) {
      completionHandler(
        [
          .list,
          .banner
        ]
      )
    } else {
      completionHandler(
        [.alert]
      )
    }
  }
  override func applicationDidBecomeActive(
    _ application: UIApplication
  ) {
    hideOverlay()
    UserDefaults.standard
      .set(
        false,
        forKey: "BiometricInProgressOverlay"
      )
  }

  override func applicationDidEnterBackground(
    _ application: UIApplication
  ) {
    showOverlay()
  }
  override func applicationWillEnterForeground(
    _ application: UIApplication
  ) {
    hideOverlay()
  }

  // MARK: - Linking / Universal Links

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    return RCTLinkingManager
      .application(
        application,
        open: url,
        options: options
      )
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping (
      [UIUserActivityRestoring]?
    ) -> Void
  ) -> Bool {
    return RCTLinkingManager
      .application(
        application,
        continue: userActivity,
        restorationHandler: restorationHandler
      )
  }
}


// MARK: - Scene life cycle
// Apps built with the iOS 27 SDK must adopt UIScene or they fail to launch. RCTAppDelegate still
// creates its window in application(_:didFinishLaunchingWithOptions:); this attaches that window to
// the scene and forwards the scene events the AppDelegate handled before.

@objc(LLSceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  private var appDelegate: AppDelegate? { UIApplication.shared.delegate as? AppDelegate }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene, let window = appDelegate?.window else { return }
    window.windowScene = windowScene
    window.frame = windowScene.coordinateSpace.bounds
    window.makeKeyAndVisible()

    if let context = connectionOptions.urlContexts.first {
      RCTLinkingManager.application(UIApplication.shared, open: context.url, options: [:])
    }
    if let activity = connectionOptions.userActivities.first {
      _ = RCTLinkingManager.application(UIApplication.shared, continue: activity, restorationHandler: { _ in })
    }
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    appDelegate?.applicationDidBecomeActive(UIApplication.shared)
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    appDelegate?.applicationWillEnterForeground(UIApplication.shared)
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    appDelegate?.applicationDidEnterBackground(UIApplication.shared)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      RCTLinkingManager.application(UIApplication.shared, open: context.url, options: [:])
    }
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    _ = RCTLinkingManager.application(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
  }
}
