import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("일반", systemImage: "gearshape")
                }

            EncodingSettingsView()
                .tabItem {
                    Label("인코딩", systemImage: "film")
                }

            TrimmingSettingsView()
                .tabItem {
                    Label("트리밍", systemImage: "scissors")
                }

            ImageSettingsView()
                .tabItem {
                    Label("이미지", systemImage: "photo")
                }
        }
        .frame(width: 480, height: 440)
    }
}
