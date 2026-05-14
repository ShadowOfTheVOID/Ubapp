import SwiftUI
import CoreImage.CIFilterBuiltins

/// Host's player UI: shows the QR for guests to join, the lobby roster, and
/// the running game state. Mirrors lib/games/mafia/mafia_screen.dart — the
/// fully-styled phase UIs (night targets, day vote, reveal, game-over) are
/// TODO; this view shows enough to drive the engine end-to-end.
struct MafiaView: View {
    @StateObject private var model = MafiaViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = model.joinUrl {
                    GroupBox("Guests join here") {
                        VStack(alignment: .leading) {
                            if let qr = QRCode.image(for: url.absoluteString) {
                                Image(uiImage: qr)
                                    .interpolation(.none)
                                    .resizable().scaledToFit()
                                    .frame(maxHeight: 220)
                            }
                            Text(url.absoluteString).font(.system(.body, design: .monospaced))
                        }
                    }
                } else {
                    Button("Start hosting") { model.startHosting() }
                        .buttonStyle(.borderedProminent)
                }

                GroupBox("Players (\(model.players.count))") {
                    ForEach(model.players, id: \.id) { p in
                        HStack {
                            Text(p.name)
                            if p.isHost { Text("(host)").foregroundStyle(.secondary) }
                            Spacer()
                            if !p.alive { Text("dead").foregroundStyle(.red) }
                        }
                    }
                }

                Text("Phase: \(String(describing: model.phase))").font(.headline)

                if model.canStart {
                    Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
                }
                if model.phase == .dayReveal {
                    Button("Continue to day vote") { model.advanceFromReveal() }
                }

                // TODO: full phase UIs (mafia night kill picker, doctor pick,
                // day vote, reveal panel, game-over modal). Port from
                // lib/games/mafia/mafia_screen.dart.
            }
            .padding()
        }
        .navigationTitle("Mafia")
        .onDisappear { model.stop() }
    }
}

@MainActor
final class MafiaViewModel: ObservableObject {
    private let server = MafiaServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: MafiaPhase = .lobby
    @Published var players: [MafiaPlayer] = []
    @Published var canStart = false

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func startHosting() {
        do {
            joinUrl = try server.start()
        } catch {
            print("HostServer failed: \(error)")
        }
        refresh()
    }
    func start() { server.hostStart() }
    func advanceFromReveal() { server.advanceFromReveal() }
    func stop() { server.stop() }

    private func refresh() {
        phase = server.engine.phase
        players = Array(server.engine.players.values).sorted { $0.id < $1.id }
        canStart = server.engine.canStart
    }
}

enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ci = filter.outputImage?.transformed(by: .init(scaleX: 8, y: 8)) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
