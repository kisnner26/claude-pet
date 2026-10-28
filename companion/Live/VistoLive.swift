import ActivityKit
import AppIntents
import SwiftUI
import VistoCore
import WidgetKit

@main
struct VistoLiveBundle: WidgetBundle {
    var body: some Widget { VistoLiveActivity() }
}

private func agentArt(_ a: String) -> PixelArt { a == "codex" ? .codex : .claude }

struct VistoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VistoActivityAttributes.self) { ctx in
            LockView(s: ctx.state).padding(16).activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { PixelSprite(art: agentArt(s.agent)).frame(width: 44, height: 44) }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(VTFormat.state(s.state)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(VTFormat.stateColor(s.state))
                        if let c = s.context { Text("ctx \(c)%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(s.askTool.map { "Permiso: \($0)" } ?? VTFormat.agentName(s.agent)).font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1)
                        Text(s.project).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let id = s.askID {
                        HStack(spacing: 10) {
                            Button(intent: LiveDecisionIntent(askID: id, allow: false)) { Label("Denegar", systemImage: "xmark").frame(maxWidth: .infinity) }.tint(.red)
                            if s.canAllow { Button(intent: LiveDecisionIntent(askID: id, allow: true)) { Label("Permitir", systemImage: "checkmark").frame(maxWidth: .infinity) }.tint(.blue) }
                        }.buttonStyle(.borderedProminent)
                        if !s.canAllow { Text("Riesgo alto: apruébalo en la Mac").font(.system(size: 10)).foregroundStyle(.orange) }
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { c in
                            Text("\(s.project) · \(VTFormat.duration(Int(c.date.timeIntervalSince(s.since))))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                PixelSprite(art: agentArt(s.agent)).frame(width: 22, height: 22)
            } compactTrailing: {
                if s.pending > 0 { Text("\(s.pending)").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(VT.amber) }
                else { Circle().fill(VTFormat.stateColor(s.state)).frame(width: 9, height: 9) }
            } minimal: {
                PixelSprite(art: agentArt(s.agent)).frame(width: 20, height: 20)
            }
            .keylineTint(VTFormat.stateColor(s.state))
        }
    }
}

struct LockView: View {
    let s: VistoActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 14) {
            PixelSprite(art: agentArt(s.agent)).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.askTool.map { "Claude pide permiso: \($0)" } ?? "\(VTFormat.agentName(s.agent)) · \(VTFormat.state(s.state))").font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1)
                Text(s.project).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                if let id = s.askID {
                    HStack(spacing: 8) {
                        Button(intent: LiveDecisionIntent(askID: id, allow: false)) { Label("Denegar", systemImage: "xmark") }.tint(.red)
                        if s.canAllow { Button(intent: LiveDecisionIntent(askID: id, allow: true)) { Label("Permitir", systemImage: "checkmark") }.tint(.blue) }
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
