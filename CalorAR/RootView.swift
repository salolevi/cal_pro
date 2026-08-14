import SwiftUI

/// Placeholder shell for Phase 0. Its only job is to make the build verifiable:
/// it reports whether the Supabase configuration actually reached the bundle,
/// which is the first thing that silently breaks on a fresh clone.
///
/// Replaced by the real tab bar (Diario / Buscar / Progreso / Perfil) in Phase 2.
struct RootView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)

                VStack(spacing: 6) {
                    Text("CalorAR")
                        .font(.largeTitle.bold())
                    Text("Contador de calorías argentino")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                configurationStatus
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var configurationStatus: some View {
        if SupabaseConfig.isConfigured {
            Label {
                Text("Conectado a \(SupabaseConfig.displayHost ?? "Supabase")")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.footnote)
            .foregroundStyle(.green)
        } else {
            Label {
                Text("Supabase sin configurar")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.footnote)
            .foregroundStyle(.orange)
        }
    }
}

#Preview {
    RootView()
}
