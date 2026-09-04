import SwiftUI

/// Three colored dots — one per study type — sitting below the play/pause
/// button, with a small tinted bubble beneath naming the active type.
///
/// The dots themselves stay unlabeled: mid-session the eye should find the
/// selection by color and position, not read a word. The bubble is the one
/// concession — it confirms *which* bucket the running minutes are landing in,
/// which is the thing a user is most likely to second-guess after a switch.
///
/// Every dot is drawn at full saturation; selection is shown by a ring and a
/// size bump, never by fading the others. Faded dots on parchment turned to
/// mud, and a switcher whose options can't be read isn't a switcher.
struct StudyTypeDots: View {
    let selected: StudyType
    let onSelect: (StudyType) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                ForEach(StudyType.allCases) { type in
                    Button { onSelect(type) } label: {
                        dot(for: type)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(type.displayName)
                    .accessibilityAddTraits(selected == type ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.eggshellDeep)
            )
            .overlay(
                Capsule().strokeBorder(Color.hairline, lineWidth: 1)
            )

            modeBubble
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
    }

    private func dot(for type: StudyType) -> some View {
        let isSelected = selected == type
        return ZStack {
            // Selection ring, always laid out so the row never shifts as the
            // selection moves between dots.
            Circle()
                .strokeBorder(type.color, lineWidth: 2)
                .frame(width: 24, height: 24)
                .opacity(isSelected ? 1 : 0)

            Circle()
                .fill(type.color)
                .frame(width: 12, height: 12)
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .shadow(color: type.color.opacity(isSelected ? 0.45 : 0), radius: 4, x: 0, y: 1)
        }
        .frame(width: 32, height: 32)   // comfortable tap target around a small dot
        .contentShape(Circle())
    }

    /// Tinted pill naming the active type. Text and tint both come from the
    /// type's own color so the bubble reads as a caption for the ringed dot.
    private var modeBubble: some View {
        Text(selected.displayName)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(0.3)
            .foregroundStyle(selected.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected.color.opacity(0.14)))
            .contentTransition(.interpolate)
            .accessibilityHidden(true)   // the ringed dot already announces itself as selected
    }
}

#Preview {
    VStack(spacing: 24) {
        StudyTypeDots(selected: .grammar) { _ in }
        StudyTypeDots(selected: .immersion) { _ in }
        StudyTypeDots(selected: .output) { _ in }
    }
    .padding(40)
    .background(Color.eggshell)
}
