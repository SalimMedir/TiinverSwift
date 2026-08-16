import SwiftUI

/// Port de `MotionTemplateGalleryView.java` — liste des modèles de mouvement sauvegardés
/// localement (`RecyclerView` → `List` SwiftUI), état vide si aucun modèle, suppression, sélection
/// applique le modèle au calque sélectionné dans l'éditeur (`AnimemesEditorState.applyTemplate`).
/// **Aperçu miniature PAS reproduit** (Android en a probablement un via une vignette rendue —
/// non détaillé par l'audit qui a scopé cette passe) : chaque ligne affiche la date de création et
/// le nombre de pistes/calques à la place.
struct MotionTemplateGalleryView: View {
    var onSelect: (MotionTemplate) -> Void
    var onClose: () -> Void

    @State private var templates: [MotionTemplate] = []

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Aucun modèle enregistré").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                onSelect(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dateLabel(template.createdAt))
                                        .font(.subheadline).bold()
                                        .foregroundStyle(.primary)
                                    Text("\(template.tracks.count) calque(s) · \(template.totalFrames) frames")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Modèles de mouvement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", action: onClose)
                }
            }
        }
        .onAppear { templates = MotionTemplateManager.loadAll() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { MotionTemplateManager.delete(id: templates[index].id) }
        templates = MotionTemplateManager.loadAll()
    }

    private func dateLabel(_ createdAtMillis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(createdAtMillis) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
