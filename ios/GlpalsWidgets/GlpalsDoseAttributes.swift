import ActivityKit
import Foundation

/// The shape of a GLPals dose Live Activity.
///
/// This file is compiled into *both* the app and the widget extension: the app
/// starts and updates the activity, the extension draws it, and ActivityKit
/// matches them up by this type. If the two copies ever disagree the activity
/// silently fails to appear, so there is one file rather than two.
///
/// Everything the island renders lives in `ContentState`, including text that
/// could arguably be static. That is deliberate — a product switch or a dose
/// change can then be pushed as an update instead of having to tear the
/// activity down and start a new one.
struct GlpalsDoseAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// When the dose is due. The island counts down to this itself.
    var dueAt: Date

    /// True once `dueAt` has passed.
    var overdue: Bool

    /// Inside the window where a fridge-kept pen should come out.
    var fridgeTip: Bool

    /// Short headline, e.g. "Shot in" or "Shot overdue".
    var title: String

    /// Supporting line: product, dose and site, or what a reminder just said.
    var detail: String

    var brand: String
    var productEmoji: String

    /// The companion's stage emoji, used where there is room for one glyph.
    var palEmoji: String

    var waterMl: Int
    var waterGoal: Int
    var proteinG: Int
    var proteinGoal: Int

    /// 0...1 progress towards today's water goal.
    var waterProgress: Double {
      guard waterGoal > 0 else { return 0 }
      return min(1, Double(waterMl) / Double(waterGoal))
    }

    /// 0...1 progress towards today's protein goal.
    var proteinProgress: Double {
      guard proteinGoal > 0 else { return 0 }
      return min(1, Double(proteinG) / Double(proteinGoal))
    }

    /// Range for a counting-down timer. Only valid while not overdue, so
    /// callers must check `overdue` first: a range whose start is after its end
    /// traps at runtime.
    var countdownRange: ClosedRange<Date> {
      let now = Date()
      return now <= dueAt ? now...dueAt : dueAt...dueAt
    }

    /// Range for a counting-up timer, used once the dose is late. The upper
    /// bound is far enough out that it keeps counting for as long as the
    /// activity can live.
    var elapsedRange: ClosedRange<Date> {
      dueAt...dueAt.addingTimeInterval(60 * 60 * 24 * 7)
    }
  }

  /// No per-activity identity is needed: there is only ever one dose countdown
  /// on screen. The name is here because `ActivityAttributes` has to carry
  /// something, and it makes the activity readable in Console logs.
  var appName: String = "GLPals"
}
