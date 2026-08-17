import SwiftUI

/// Port de `advertising/ui/BoostDashboardFragment.java` (entier, 2026-08-18, P1) — vue d'ensemble
/// (`boost/overviews/{userId}`, ligne d'en-tête) + liste paginée des boosts existants
/// (`boost/myboost/{userId}/{limit}/{offset}`, pagination infinie seuil 4 items avant la fin,
/// `visibleThreshold`).
struct BoostDashboardView: View {
    let userId: String

    @State private var overview: AdsData?
    @State private var boosts: [AdsData] = []
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var offset = 0
    private let limit = 10

    var body: some View {
        List {
            if let overview {
                Section("Vue d'ensemble") {
                    overviewRow(overview)
                }
            }
            Section("Mes boosts") {
                if boosts.isEmpty && !isLoading {
                    Text("Aucun boost pour le moment").foregroundStyle(.secondary)
                }
                ForEach(boosts) { boost in
                    NavigationLink {
                        BoostDetailView(userId: userId, boost: boost)
                    } label: {
                        boostRow(boost)
                    }
                    .onAppear {
                        if boost.id == boosts.last?.id { Task { await loadMore() } }
                    }
                }
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
        .navigationTitle("Tableau de bord")
        .task {
            async let overviewTask: () = loadOverview()
            async let boostsTask: () = loadMore()
            _ = await (overviewTask, boostsTask)
        }
        .refreshable {
            offset = 0
            reachedEnd = false
            boosts = []
            await loadOverview()
            await loadMore()
        }
    }

    private func overviewRow(_ data: AdsData) -> some View {
        HStack(spacing: 16) {
            statColumn("\(data.views ?? 0)", "Vues")
            statColumn("\(data.likes ?? 0)", "J'aime")
            statColumn("\(data.followers ?? 0)", "Abonnés")
            statColumn(data.total_spent ?? "0", "Dépensé")
        }
    }

    private func statColumn(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func boostRow(_ boost: AdsData) -> some View {
        HStack(spacing: 12) {
            CDNAsyncImage(url: boost.resolvedObjectUrl.flatMap(URL.init)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Color(.secondarySystemBackground)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(boost.message?.isEmpty == false ? boost.message! : (boost.objective ?? "")).lineLimit(1)
                Text("\(boost.status ?? "") · \(boost.duration_days ?? "0")j · \(Int(boost.budget_points ?? 0)) pts")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func loadOverview() async {
        overview = try? await AdsRepository.shared.fetchOverview(userId: userId)
    }

    private func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        let page = (try? await AdsRepository.shared.fetchMyBoosts(userId: userId, limit: limit, offset: offset)) ?? []
        if page.isEmpty {
            reachedEnd = true
        } else {
            boosts.append(contentsOf: page)
            offset += limit
        }
    }
}
