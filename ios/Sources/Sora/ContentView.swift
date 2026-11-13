import SwiftUI

/// One screen: paste a magnet or a media URL, Sora resolves it to a loopback
/// HTTP stream and plays it.
///
/// Sora ships no catalogue and no addons. The only input is a magnet or a URL
/// the user already owns or is licensed to watch.
struct ContentView: View {
    @StateObject private var model = PlayerModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("magnet:?xt=… atau https://…", text: $model.input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.play() }

                Button("Putar") { model.play() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
            }
            .padding(12)

            Text(model.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            PlayerView(player: model.player)
                .background(.black)
        }
        .background(Color(red: 0.03, green: 0.03, blue: 0.04))
        .ignoresSafeArea(edges: .bottom)
        .onDisappear { model.shutdown() }
    }
}

#Preview {
    ContentView()
}
