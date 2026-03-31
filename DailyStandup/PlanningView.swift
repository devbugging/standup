import SwiftUI

struct PlanningView: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Planning")
                            .font(.system(size: 20, weight: .bold))
                        Text("Beta")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }

                    Text("Monthly planning is coming soon. This feature will help you review your standup history, track progress across projects, and plan ahead for the month.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 420, minHeight: 300)
    }
}
