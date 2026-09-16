import ActivityKit
import SwiftUI
import WidgetKit

/// The GLPals palette, mirroring `Palette` in lib/theme.dart. Kept as literals
/// rather than an asset catalog so the extension has no resources to keep in
/// step with the Flutter side.
private enum Pal {
  static let coral = Color(red: 1.0, green: 0.482, blue: 0.330)
  static let mint = Color(red: 0.180, green: 0.769, blue: 0.714)
  static let sky = Color(red: 0.298, green: 0.788, blue: 0.941)
  static let sunshine = Color(red: 1.0, green: 0.820, blue: 0.400)
  static let berry = Color(red: 0.937, green: 0.278, blue: 0.435)
  static let cream = Color(red: 1.0, green: 0.973, blue: 0.949)

  /// Overdue gets its own colour, the same way the in-app banner does: it is
  /// the one state that should not be easy to glance past.
  static func accent(_ overdue: Bool) -> Color { overdue ? berry : coral }
}

@main
struct GlpalsWidgetsBundle: WidgetBundle {
  var body: some Widget {
    GlpalsDoseActivity()
  }
}

/// The dose countdown, on the Lock Screen and in the Dynamic Island.
struct GlpalsDoseActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GlpalsDoseAttributes.self) { context in
      LockScreenCard(state: context.state)
        .activityBackgroundTint(Color.black.opacity(0.45))
        .activitySystemActionForegroundColor(Pal.cream)
    } dynamicIsland: { context in
      let state = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            Text(state.productEmoji)
            VStack(alignment: .leading, spacing: 1) {
              Text(state.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
              Text(state.brand)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            }
          }
          .padding(.leading, 4)
        }

        DynamicIslandExpandedRegion(.trailing) {
          CountdownText(state: state)
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(Pal.accent(state.overdue))
            .padding(.trailing, 4)
        }

        DynamicIslandExpandedRegion(.center) {
          Text(state.detail)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }

        DynamicIslandExpandedRegion(.bottom) {
          GoalBars(state: state)
            .padding(.horizontal, 4)
        }
      } compactLeading: {
        Text(state.overdue ? "⚠️" : state.productEmoji)
      } compactTrailing: {
        CountdownText(state: state)
          .font(.caption.monospacedDigit())
          .foregroundStyle(Pal.accent(state.overdue))
          .frame(maxWidth: 62)
      } minimal: {
        // One glyph, so the pal gets the spot rather than a clock nobody can
        // read at this size.
        Text(state.overdue ? "⚠️" : state.palEmoji)
      }
      .keylineTint(Pal.accent(state.overdue))
    }
  }
}

/// The live clock. iOS redraws this on its own, so the countdown keeps ticking
/// with nothing of the app's running.
private struct CountdownText: View {
  let state: GlpalsDoseAttributes.ContentState

  var body: some View {
    if state.overdue {
      // Counting up says how late it is, which is more use than a frozen zero.
      Text(timerInterval: state.elapsedRange, countsDown: false)
    } else {
      Text(timerInterval: state.countdownRange, countsDown: true)
    }
  }
}

/// Today's two act-on-them numbers, so a water or meal reminder that lands in
/// the island has something to land against.
private struct GoalBars: View {
  let state: GlpalsDoseAttributes.ContentState

  var body: some View {
    HStack(spacing: 12) {
      bar(emoji: "💧",
          value: state.waterProgress,
          label: "\(state.waterMl)/\(state.waterGoal) ml",
          tint: Pal.sky)
      bar(emoji: "🥩",
          value: state.proteinProgress,
          label: "\(state.proteinG)/\(state.proteinGoal) g",
          tint: Pal.mint)
    }
  }

  private func bar(emoji: String, value: Double, label: String, tint: Color)
    -> some View
  {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Text(emoji).font(.caption2)
        Text(label)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      ProgressView(value: value)
        .progressViewStyle(.linear)
        .tint(tint)
    }
  }
}

/// The Lock Screen and banner presentation: the same information with room to
/// breathe.
private struct LockScreenCard: View {
  let state: GlpalsDoseAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(state.productEmoji).font(.title3)
        VStack(alignment: .leading, spacing: 1) {
          Text(state.title)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(state.detail)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Pal.cream)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        Spacer(minLength: 8)
        CountdownText(state: state)
          .font(.title2.weight(.semibold).monospacedDigit())
          .foregroundStyle(Pal.accent(state.overdue))
      }

      if state.fridgeTip {
        Text("🧊 Take the pen out so it is not cold going in.")
          .font(.caption2)
          .foregroundStyle(Pal.sunshine)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }

      GoalBars(state: state)
    }
    .padding(14)
  }
}
