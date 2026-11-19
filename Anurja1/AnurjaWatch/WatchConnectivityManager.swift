import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, WatchConnectivityManaging {
    var onSnapshot: ((GlucoseSnapshot) -> Void)?
    private var pendingMeals: [[String: Any]] = []
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func sendMeal(food: String, id: String) {
        let payload = CompanionMessage.mealPayload(food: food, id: id)
        guard let session, session.activationState == .activated else {
            pendingMeals.append(payload)
            return
        }
        deliver(payload, session: session)
    }

    func handle(payload: [String: Any]) {
        guard let snapshot = CompanionMessage.snapshot(from: payload) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snapshot)
        }
    }

    private func flush() {
        guard let session, session.activationState == .activated else { return }
        let queued = pendingMeals
        pendingMeals.removeAll()
        queued.forEach { deliver($0, session: session) }
    }

    private func deliver(_ payload: [String: Any], session: WCSession) {
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                self?.deliverLater(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func deliverLater(_ payload: [String: Any]) {
        guard let session else { return }
        session.transferUserInfo(payload)
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        _ = error
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
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
            self?.flush()
        }
    }
}
