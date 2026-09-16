import ActivityKit
import Flutter
import Foundation

/// Bridges `lib/live_activity.dart` to ActivityKit.
///
/// Dart owns every decision — whether there should be an activity, what it
/// says, when it is worth buzzing — so this side stays a forwarder: it starts
/// an activity if there is not one, updates the one there is, and ends it when
/// Dart says to.
///
/// There is deliberately no stored `Activity` handle. ActivityKit already keeps
/// the list, and reading it back means an activity started before the app was
/// last killed is still found and reused rather than being orphaned on the Lock
/// Screen with a second one stacked on top.
///
/// Registered on both Flutter engines: the main one, and the headless one the
/// notifications plugin starts for action buttons. On that second engine only
/// `update` and `end` can succeed — ActivityKit refuses to *start* an activity
/// from an app that is not in the foreground — so a "+1 glass" from the Lock
/// Screen refreshes an island that is already up but cannot raise a new one.
enum LiveActivityBridge {
  static let channelName = "glpals/live_activity"

  static func register(with registry: FlutterPluginRegistry) {
    // Nil only when this key was already registered on this engine.
    guard let registrar = registry.registrar(forPlugin: "GlpalsLiveActivity")
    else { return }
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "sync":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(
            code: "bad_args", message: "sync needs a map", details: nil))
          return
        }
        handle(args: args, result: result)
      case "end":
        end(result: result)
      case "supported":
        result(isSupported)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Live Activities need iOS 16.2 for the `ActivityContent` API this uses, and
  /// the user can switch them off for the app in Settings.
  private static var isSupported: Bool {
    if #available(iOS 16.2, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    return false
  }

  private static func handle(args: [String: Any], result: @escaping FlutterResult) {
    if #available(iOS 16.2, *) {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        // Switched off for GLPals in Settings. Not an error: the app carries on
        // and the island simply stays empty.
        result(false)
        return
      }

      let state = contentState(from: args)
      let staleDate = date(args["stale_ms"])
      let alert = args["alert"] as? Bool ?? false
      let alertTitle = args["alert_title"] as? String ?? ""
      let alertBody = args["alert_body"] as? String ?? ""

      // On the main actor so ActivityKit is driven from the platform thread and
      // the Flutter result is delivered there too, which the engine requires.
      Task { @MainActor in
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let existing = Activity<GlpalsDoseAttributes>.activities.first {
          if alert, !alertTitle.isEmpty {
            // An update carrying an alert is what makes the island expand and
            // buzz — as close as iOS gets to putting a notification there.
            await existing.update(
              content,
              alertConfiguration: AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: alertTitle),
                body: LocalizedStringResource(stringLiteral: alertBody),
                sound: .default))
          } else {
            await existing.update(content)
          }
          result(true)
          return
        }

        do {
          _ = try Activity<GlpalsDoseAttributes>.request(
            attributes: GlpalsDoseAttributes(),
            content: content,
            pushType: nil)
          result(true)
        } catch {
          // Expected from the headless notification engine, which cannot start
          // one; anything else is worth seeing in Console.
          NSLog("GLPals live activity request failed: \(error.localizedDescription)")
          result(false)
        }
      }
    } else {
      result(false)
    }
  }

  private static func end(result: @escaping FlutterResult) {
    if #available(iOS 16.2, *) {
      Task { @MainActor in
        // Immediate rather than the default lingering dismissal: once the dose
        // is logged the countdown is not just finished, it is wrong.
        for activity in Activity<GlpalsDoseAttributes>.activities {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        result(true)
      }
    } else {
      result(false)
    }
  }

  private static func contentState(from args: [String: Any])
    -> GlpalsDoseAttributes.ContentState
  {
    GlpalsDoseAttributes.ContentState(
      dueAt: date(args["due_ms"]) ?? Date(),
      overdue: args["overdue"] as? Bool ?? false,
      fridgeTip: args["fridge_tip"] as? Bool ?? false,
      title: args["title"] as? String ?? "",
      detail: args["detail"] as? String ?? "",
      brand: args["brand"] as? String ?? "",
      productEmoji: args["product_emoji"] as? String ?? "💉",
      palEmoji: args["pal_emoji"] as? String ?? "🥚",
      waterMl: int(args["water_ml"]),
      waterGoal: int(args["water_goal"]),
      proteinG: int(args["protein_g"]),
      proteinGoal: int(args["protein_goal"]))
  }

  /// Dart sends epoch milliseconds; the platform channel may hand them over as
  /// `Int` or `NSNumber` depending on magnitude, so normalise through `NSNumber`.
  private static func date(_ value: Any?) -> Date? {
    guard let ms = (value as? NSNumber)?.doubleValue else { return nil }
    return Date(timeIntervalSince1970: ms / 1000)
  }

  private static func int(_ value: Any?) -> Int {
    (value as? NSNumber)?.intValue ?? 0
  }
}
