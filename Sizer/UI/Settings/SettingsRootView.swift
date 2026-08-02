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

            WindowSnapSettingsView()
                .tabItem {
                    Label("창 스냅", systemImage: "rectangle.split.2x1")
                }

            KeepAwakeSettingsView()
                .tabItem {
                    Label("꺼짐 방지", systemImage: "sun.max")
                }
        }
        .frame(width: 520, height: 440)
    }
}
