import SwiftUI

struct PreferencesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.title2).bold()
            Text("Hotkey, save directory, image format and other preferences will live here.")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(width: 460, height: 280)
    }
}
