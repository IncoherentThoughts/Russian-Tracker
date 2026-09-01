import SwiftUI

/// Three colored dots — one per study type — sitting below the play/pause
/// button. Deliberately unlabeled: mid-session the eye should find the
/// selection by color and position, not read a word. The types are named on the
/// Stats screen, where the all-time ring's legend does the teaching.
///
/// VoiceOver is the exception to "unlabeled" — three anonymous buttons would be
/// unusable, so each carries its type name.
struct StudyTypeDots: View {
    let selected: StudyType
    let onSelect: (StudyType) -> Void

    var body: some View {
        HStack(spacing: 20) {
            ForEach(StudyType.allCases) { type in
                Button { onSelect(type) } label: {
                    dot(for: type)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(type.displayName)
                .accessibilityAddTraits(selected == type ? [.isSelected] : [])
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selected)
    }

    private func dot(for type: StudyType) -> some View {
        let isSelected = selected == type
        return ZStack {
            // Selection ring, always laid out so the row never shifts as the
            // selection moves between dots.
            Circle()
                .stroke(type.color.opacity(0.45), lineWidth: 1.5)
                .frame(width: 20, height: 20)
                .opacity(isSelected ? 1 : 0)

            Circle()
                .fill(type.color)
                .frame(width: 10, height: 10)
                .opacity(isSelected ? 1 : 0.4)
                .scaleEffect(isSelected ? 1.15 : 1.0)
        }
        .frame(width: 30, height: 30)   // comfortable tap target around a small dot
        .contentShape(Circle())
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
