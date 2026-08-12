import SwiftUI

/// Port de l'écran post-décroché de `CallActivity.java`/`IncomingCallActivity.java` (mise en page
/// `activity_call.xml`/`activity_receive_call.xml`, pas lues — reconstruites depuis les
/// `findViewById` observés : titre, sous-titre d'état, boutons muet/haut-parleur/raccrocher).
///
/// **Capteur de proximité/wake lock/notification à actions Android NON reproduits ici,
/// délibérément** : CallKit gère nativement l'écran d'appel système (accepter/refuser, verrouillage,
/// app Téléphone) ET le comportement de proximité pendant un appel actif — cette vue SwiftUI n'est
/// affichée qu'APRÈS que CallKit a déjà géré la sonnerie/réponse, elle correspond au "corps"
/// (minuteur, muet, haut-parleur) affiché une fois l'appel décroché, pas à l'écran de sonnerie
/// lui-même (remplacé par l'écran système CallKit, aucune vue SwiftUI équivalente nécessaire).
struct CallView: View {
    @ObservedObject var coordinator: CallCoordinator = .shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(callerName)
                .font(.title2).bold()
            Text(statusText)
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 32) {
                controlButton(systemImage: coordinator.isMuted ? "mic.slash.fill" : "mic.fill", active: coordinator.isMuted) {
                    // Port de `mute.setOnClickListener` — bouton custom qui demande la même
                    // transaction CallKit qu'un appui sur le bouton muet natif (`CXSetMutedCallAction`),
                    // pour que l'état reste cohérent avec l'écran système.
                    if let uuid = coordinator.activeCallUUID { CallKitManager.shared.setMuted(uuid: uuid, muted: !coordinator.isMuted) }
                }
                controlButton(systemImage: coordinator.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill", active: coordinator.isSpeakerOn) {
                    coordinator.toggleSpeaker()
                }
            }
            Spacer()
            Button {
                if let uuid = coordinator.activeCallUUID { CallKitManager.shared.requestEndCall(uuid: uuid) }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.red))
            }
            .padding(.bottom, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var callerName: String {
        switch coordinator.state {
        case .outgoing(let name), .incoming(let name): return name
        default: return ""
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .idle, .ended: return ""
        case .outgoing: return "Appel en cours…" // R.string.calling
        case .incoming: return "Appel entrant…" // R.string.voice_call_message
        case .connecting: return "Connexion…" // R.string.connecting
        case .connected: return "Connecté" // R.string.connected
        }
    }

    private func controlButton(systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(active ? Color.accentColor : Color(.secondarySystemBackground)))
        }
    }
}
