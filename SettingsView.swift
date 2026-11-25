import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var theme: AppTheme

    private let accents = ["8CB8F2", "7C5CFF", "FF5C8A", "FF8A3D", "2ECC71",
                           "FFD23F", "1ABC9C", "E74C3C", "B388FF", "FFFFFF"]
    private let backgrounds = ["0F1424", "000000", "1B1B1F", "101A12", "2A1633",
                               "F2F4FA", "FFFFFF", "FFF4E5", "E8F5E9", "FCE4EC"]

    private var cols: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: 5) }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        appearanceCard
                        accentCard
                        backgroundCard
                        aboutCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.bg, for: .navigationBar)
        }
    }

    var appearanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tema").font(.headline)
                Picker("Tema", selection: $theme.appearance) {
                    ForEach(AppTheme.Appearance.allCases) { a in Text(a.title).tag(a) }
                }
                .pickerStyle(.segmented)
                .disabled(theme.bgHex != nil)
                if theme.bgHex != nil {
                    Text("Com cor de fundo personalizada, o tema claro/escuro acompanha a cor escolhida.")
                        .font(.caption).foregroundColor(theme.soft)
                }
            }
        }
    }

    var accentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cor de destaque").font(.headline)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(accents, id: \.self) { hex in
                        swatch(hex, selected: theme.accentHex.uppercased() == hex) { theme.accentHex = hex }
                    }
                }
                ColorPicker("Escolher outra cor",
                            selection: Binding(
                                get: { theme.accent },
                                set: { theme.accentHex = UIColor($0).hexString }),
                            supportsOpacity: false)
            }
        }
    }

    var backgroundCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cor de fundo").font(.headline)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(backgrounds, id: \.self) { hex in
                        swatch(hex, selected: theme.bgHex?.uppercased() == hex) { theme.bgHex = hex }
                    }
                }
                ColorPicker("Escolher outra cor",
                            selection: Binding(
                                get: { theme.bgHex.map { Color(uiColor: UIColor(hex: $0)) } ?? theme.bg },
                                set: { theme.bgHex = UIColor($0).hexString }),
                            supportsOpacity: false)
                Button("Voltar ao fundo padrão") { theme.bgHex = nil }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.accent)
                    .disabled(theme.bgHex == nil)
            }
        }
    }

    var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sobre o som nas figurinhas").font(.headline)
                Text("O WhatsApp liberou figurinhas com som, mas a importação de pacotes de apps como este ainda não aceita áudio. Quando a API oficial sair, o som já fica guardado em cada figurinha e dá para ligar a importação.")
                    .font(.caption).foregroundColor(theme.soft)
            }
        }
    }

    private func swatch(_ hex: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let ui = UIColor(hex: hex)
        return Button(action: action) {
            Circle()
                .fill(Color(uiColor: ui))
                .aspectRatio(1, contentMode: .fit)
                .overlay(Circle().stroke(theme.text.opacity(0.2), lineWidth: 1))
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(ui.luminance > 0.6 ? Color.black : Color.white)
                    }
                }
        }
    }
}
