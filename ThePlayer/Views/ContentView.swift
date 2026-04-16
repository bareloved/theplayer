import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            Text("Sections")
                .frame(minWidth: 220)
        } detail: {
            Text("Open an audio file to get started")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
