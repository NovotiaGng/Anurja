import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, WatchConnectivityManaging {
    var onMeal: ((String, String) -> Void)?
    private var pending: GlucoseSnapshot?
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func push(_ snapshot: GlucoseSnapshot) {
        pending = snapshot
        sendPending()
    }

    func handle(payload: [String: Any]) {
        guard let meal = CompanionMessage.meal(from: payload) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onMeal?(meal.food, meal.id)
        }
    }

    private func sendPending() {
        guard let session, session.activationState == .activated, let pending else { return }
        try? session.updateApplicationContext(CompanionMessage.snapshotPayload(pending))
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        _ = error
        DispatchQueue.main.async { [weak self] in
            self?.sendPending()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(payload: message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(payload: message)
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(payload: userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(payload: applicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.sendPending()
        }
    }
}
