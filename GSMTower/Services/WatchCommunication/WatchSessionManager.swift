import Foundation
import UIKit
import WatchConnectivity

class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    @Published var receivedPoint: Point?

    private override init() {
        super.init()
        activate()
    }

    func activate() {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(text: String) {
        WCSession.default.sendMessage(
            ["message": text],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    // iOS: Wyślij punkt do zegarka
    func sendPointToWatch(point: Point) {
        guard WCSession.default.isReachable else { return }
        let data: [String: Any] = [
            "latitude": point.latitude,
            "longitude": point.longitude,
            "city": point.details.city,
            "location": point.details.location,
            "stationId": point.details.stationId,
            "teryt": point.details.teryt,
        ]
        WCSession.default.sendMessage(
            data,
            replyHandler: nil,
            errorHandler: nil
        )
    }

    // watchOS: Odbierz wiadomość
    func session(_ session: WCSession, didReceiveMessage message: [String: Any])
    {
        print(message)
        guard let latitude = message["latitude"] as? Double,
            let longitude = message["longitude"] as? Double,
            let city = message["city"] as? String,
            let location = message["location"] as? String,
            let stationId = message["stationId"] as? String,
            let teryt = message["teryt"] as? String
        else { return }
        let details = PointDetails(
            city: city,
            location: location,
            stationId: stationId,
            teryt: teryt
        )
        let point = Point(
            longitude: longitude,
            latitude: latitude,
            details: details,
            permissions: []
        )
        DispatchQueue.main.async {
            self.receivedPoint = point
        }
    }

    // Wymagane metody protokołu WCSessionDelegate
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {

    }

    #if os(iOS)
        func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }

        func sessionDidBecomeInactive(_ session: WCSession) {
            session.activate()
        }
    #endif
}
