import Foundation
import SwiftData
import UserNotifications

/// Which running timers deserve a "still running" nudge, and when. Pure so it's testable; the
/// thresholds are per activity and live in the App Group defaults (Settings › Notifications).
enum ForgottenTimerPolicy {
    static let enabledKey = "forgottenTimerAlertsEnabled"
    static var isEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BB_TIMER_ALERT_SECONDS"] != nil { return true }
        #endif
        return SharedDefaults.suite.bool(forKey: enabledKey)
    }

    /// The threshold choices Settings offers, in seconds.
    static let choices: [TimeInterval] = [1800, 3600, 7200, 14_400, 28_800, 43_200, 86_400]

    static func thresholdKey(_ activity: TimerActivity) -> String { "forgottenTimerThreshold.\(activity.rawValue)" }

    static func defaultThreshold(_ activity: TimerActivity?) -> TimeInterval {
        switch activity {
        case .feeding, .pumping: return 7200
        case .sleep: return 43_200
        case .tummyTime: return 3600
        case nil: return 14_400 // ponytail: untyped timers aren't configurable; add a row if asked
        }
    }

    /// The configured threshold for an activity. `BB_TIMER_ALERT_SECONDS=<n>` (DEBUG) turns alerts
    /// on and overrides every threshold so the alert can be exercised without waiting hours.
    static func threshold(for activity: TimerActivity?) -> TimeInterval {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["BB_TIMER_ALERT_SECONDS"], let n = Double(s) {
            return n
        }
        #endif
        guard let activity else { return defaultThreshold(nil) }
        let stored = SharedDefaults.suite.double(forKey: thresholdKey(activity))
        return stored > 0 ? stored : defaultThreshold(activity)
    }

    struct Request: Equatable {
        let id: String
        let fireDate: Date
        let title: String
        let body: String
        let url: String
    }

    static func identifier(for timer: LocalEntity) -> String { "timer-\(timer.localID.uuidString)" }

    /// The notification a running timer should fire once it passes its threshold.
    static func request(for timer: LocalEntity, childName: String?,
                        threshold: TimeInterval? = nil) -> Request {
        let activity = TimerActivity(timer: timer)
        let limit = threshold ?? self.threshold(for: activity)
        let name = activity?.timerName ?? (timer.payloadObject["name"] as? String) ?? "Timer"
        let owner = childName.map { "\($0)'s " } ?? ""
        return Request(
            id: identifier(for: timer),
            fireDate: timer.timestamp.addingTimeInterval(limit),
            title: "\(name) timer still running",
            body: "\(owner)\(name.lowercased()) timer has been running for "
                + "\(EntityFormatting.formatInterval(limit)). Tap to stop it.",
            url: "babybuddy://timer/\(timer.localID.uuidString)")
    }

    /// Diff wanted requests against what the notification center already holds: schedule what's
    /// missing or moved, drop what no longer corresponds to a running timer. A request that has
    /// already been delivered is left alone so a timer nags once, not on every foreground; one
    /// whose time has already passed is scheduled "now" and so can't be date-matched — it is
    /// kept as long as it is pending at all.
    static func plan(wanted: [Request], pending: [String: Date], delivered: Set<String>,
                     now: Date = .now) -> (add: [Request], remove: [String]) {
        let wantedIDs = Set(wanted.map(\.id))
        let add = wanted.filter { request in
            guard !delivered.contains(request.id), let scheduled = pending[request.id] else {
                return !delivered.contains(request.id)
            }
            return request.fireDate > now && scheduled != request.fireDate
        }
        let remove = pending.keys.filter { $0.hasPrefix("timer-") && !wantedIDs.contains($0) }
        return (add, remove.sorted())
    }
}

/// Keeps the "forgotten timer" local notifications in step with the running timers. Mirrors
/// ``LiveActivityManager``: one idempotent ``reconcile()`` that ``LiveActivityManager/reconcile()``
/// calls, so every timer start/stop/discard and app foreground already covers it.
@MainActor
final class ForgottenTimerAlerts {
    static let shared = ForgottenTimerAlerts()
    private let center = UNUserNotificationCenter.current()

    func reconcile() async {
        let pending = await center.pendingNotificationRequests()
        let pendingTimerIDs = pending.map(\.identifier).filter { $0.hasPrefix("timer-") }
        guard ForgottenTimerPolicy.isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: pendingTimerIDs)
            return
        }
        // The setting can arrive on before permission was ever asked (a restored App Group
        // default); ask now rather than schedule alerts that can never show.
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = await requestAuthorization()
        }
        let pendingDates = Dictionary(uniqueKeysWithValues: pending.compactMap { request -> (String, Date)? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return (request.identifier, date)
        })
        let delivered = Set(await center.deliveredNotifications().map(\.request.identifier))
        let wanted = wantedRequests()
        let plan = ForgottenTimerPolicy.plan(wanted: wanted, pending: pendingDates, delivered: delivered)

        center.removePendingNotificationRequests(withIdentifiers: plan.remove)
        // A stopped timer's delivered banner is stale too; a running timer's stays (nag once).
        let wantedIDs = Set(wanted.map(\.id))
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            $0.hasPrefix("timer-") && !wantedIDs.contains($0)
        })
        for request in plan.add {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.userInfo = ["url": request.url]
            // A timer already past its threshold (app opened hours later) fires straight away.
            let fire = max(request.fireDate, Date().addingTimeInterval(1))
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
        }
    }

    /// Ask for permission; returns whether alerts may be shown. Called from the Settings toggle.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Every running timer in the shared store as a wanted request. Opens its own container, like
    /// the Live Activity manager, so widget-started timers are seen too.
    private func wantedRequests() -> [ForgottenTimerPolicy.Request] {
        guard let container = try? ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        else { return [] }
        let context = ModelContext(container)
        let timers = (try? context.fetch(FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == "timer" }))) ?? []
        let children = (try? context.fetch(FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == "child" }))) ?? []
        return timers.filter { $0.syncState != .pendingDelete }.map { timer in
            let child = children.first { $0.serverID == timer.childID }
            let first = child?.payloadObject["first_name"] as? String
            return ForgottenTimerPolicy.request(for: timer, childName: first.flatMap { $0.isEmpty ? nil : $0 })
        }
    }
}

/// Routes a tapped timer alert into the app (the Stop sheet, via the existing deep link) and lets
/// one show as a banner while the app is in the foreground.
final class TimerAlertDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let router: DeepLinkRouter
    init(router: DeepLinkRouter) { self.router = router }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound] // keep it in Notification Center if the banner is missed
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let raw = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: raw) {
            await MainActor.run { router.handle(url) }
        }
    }
}
