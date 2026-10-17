//
//  ScaleManager.swift
//  ScaleSync
//
//  CoreBluetooth engine for two kinds of scale.
//
//  Medisana BS4xx/6xx (reverse-engineered protocol):
//    1. Scan for service 0x78B2 (the scale only advertises while awake,
//       i.e. shortly after someone steps on it).
//    2. Connect, discover the service + characteristics.
//    3. Enable indications on 0x8A22 (composition), 0x8A21 (weight), 0x8A82 (person).
//    4. Write time-sync command to 0x8A81 — this triggers the scale to send
//       ALL stored measurements (so nothing is lost if your phone was away).
//
//  DIY ESP32 scale (Bluetooth SIG Weight Scale Service 0x181D, see
//  docs/esp32-scale-spec.md): connect, subscribe to 0x2A9D and read the
//  battery level. The scale indicates one live reading and hangs up.
//
//  After the first successful connection each peripheral identifier is
//  stored and the app issues a pending connect: iOS will wake the app in the
//  background whenever a scale powers up its radio. Requires the
//  "bluetooth-central" background mode.
//

import Foundation
import Combine
import CoreBluetooth
import SwiftData

struct BLELogLine: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}

enum ScaleStatus: Equatable {
    case bluetoothOff
    case idle
    case scanning
    case connecting
    case syncing
    case done(Date)

    var label: String {
        switch self {
        case .bluetoothOff: return "Bluetooth is off"
        case .idle: return "Waiting for scale"
        case .scanning: return "Listening…"
        case .connecting: return "Connecting…"
        case .syncing: return "Syncing…"
        case .done(let d): return "Synced \(d.formatted(date: .omitted, time: .shortened))"
        }
    }

    /// The scale is talking to the phone right now.
    var isBusy: Bool {
        switch self {
        case .connecting, .syncing: return true
        default: return false
        }
    }
}

enum ScaleKind: String {
    case medisana, diy
}

final class ScaleManager: NSObject, ObservableObject {

    @Published var status: ScaleStatus = .idle
    @Published var log: [BLELogLine] = []
    /// Persisted through the saved peripheral identifier, so a relaunch doesn't
    /// show "no scale" until the next weigh-in.
    @Published private(set) var isPaired = false
    @Published private(set) var isDIYPaired = false
    @Published private(set) var diyName: String?
    @Published private(set) var diyBattery: Int?
    @Published var newReadingsThisSession = 0
    /// When each kind of scale last delivered a reading.
    @Published private(set) var lastSeen: [ScaleKind: Date] = [:]

    private var central: CBCentralManager!
    private var scale: CBPeripheral?
    private var diy: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var indicationsPending = 0
    private var syncWorkItem: DispatchWorkItem?
    private var scanStopWorkItem: DispatchWorkItem?
    private var serviceDiscoveryRetries = 0
    /// After a background relaunch, both the restored pending connect and our
    /// own reconnect report `didConnect` for the same link. Only the first one
    /// may start service discovery, or every later step runs twice.
    private var sessionStarted = false

    private struct UnrecognizedWeighIn {
        let weightKg: Double
        let slot: Int?
        let date: Date
    }

    /// Weigh-ins in the current connection that the scale couldn't assign to
    /// a profile. Reported once, when the scale hangs up.
    private var unrecognizedThisSession: [UnrecognizedWeighIn] = []

    /// The scale starts advertising the instant someone steps on it, so we
    /// connect at the *beginning* of a weigh-in. Two measured constraints
    /// bracket when we may ask for the data dump:
    ///
    ///  - Too early (~1 s): the scale answers with a half-finished measurement
    ///    — no user id, zeroed body composition — and ends the session.
    ///  - Too late: an idle session is dropped by the scale after about 8 s.
    ///
    /// 5 s sits inside that window. Even when the current weigh-in is still
    /// incomplete, nothing is lost — the scale stores measurements internally
    /// and re-sends them on the next connection.
    private let measurementSettleDelay: TimeInterval = 5

    private let modelContainer: ModelContainer
    private let health: HealthSync

    private let serviceUUID = CBUUID(string: ScaleGATT.service)
    private let weightUUID = CBUUID(string: ScaleGATT.weightChar)
    private let featureUUID = CBUUID(string: ScaleGATT.featureChar)
    private let personUUID = CBUUID(string: ScaleGATT.personChar)
    private let commandUUID = CBUUID(string: ScaleGATT.commandChar)

    private let wssUUID = CBUUID(string: WeightScaleGATT.service)
    private let wssMeasurementUUID = CBUUID(string: WeightScaleGATT.measurementChar)
    private let batteryServiceUUID = CBUUID(string: WeightScaleGATT.batteryService)
    private let batteryLevelUUID = CBUUID(string: WeightScaleGATT.batteryLevelChar)

    private var knownPeripheralID: UUID? {
        get { UserDefaults.standard.string(forKey: "knownPeripheralID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "knownPeripheralID") }
    }

    private var knownDIYPeripheralID: UUID? {
        get { UserDefaults.standard.string(forKey: "knownDIYPeripheralID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "knownDIYPeripheralID") }
    }

    var epoch: ScaleTimeEpoch {
        ScaleTimeEpoch(rawValue: UserDefaults.standard.string(forKey: "scaleEpoch") ?? "") ?? .year2010
    }

    init(modelContainer: ModelContainer, health: HealthSync) {
        self.modelContainer = modelContainer
        self.health = health
        super.init()
        isPaired = knownPeripheralID != nil
        isDIYPaired = knownDIYPeripheralID != nil
        diyName = UserDefaults.standard.string(forKey: "diyScaleName")
        for kind in [ScaleKind.medisana, .diy] {
            let t = UserDefaults.standard.double(forKey: "lastSeen.\(kind.rawValue)")
            if t > 0 { lastSeen[kind] = Date(timeIntervalSince1970: t) }
        }
        if let last = lastSeen.values.max() { status = .done(last) }
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "ScaleSync.central"]
        )
    }

    // MARK: - Public API

    /// Kick off a scan / (re)connect. Safe to call any time.
    func syncNow() {
        guard central.state == .poweredOn else { return }
        newReadingsThisSession = 0
        if let peripheral = scale, peripheral.state == .connected {
            appendLog("Already connected — requesting stored measurements")
            requestMeasurements(from: peripheral)
        } else {
            connectOrScan()
        }
    }

    /// Listen for any scale for a minute (Household › Add a scale).
    func addScale() {
        guard central.state == .poweredOn else { return }
        startScan(for: [serviceUUID, wssUUID], timeout: 60)
    }

    func forgetScale() {
        syncWorkItem?.cancel()
        syncWorkItem = nil
        if let p = scale { central.cancelPeripheralConnection(p) }
        scale = nil
        knownPeripheralID = nil
        isPaired = false
        appendLog("Forgot saved scale")
        connectOrScan()
    }

    func forgetDIYScale() {
        if let p = diy { central.cancelPeripheralConnection(p) }
        diy = nil
        knownDIYPeripheralID = nil
        isDIYPaired = false
        diyBattery = nil
        appendLog("Forgot DIY scale")
    }

    // MARK: - Connection

    private func connectOrScan() {
        guard central.state == .poweredOn else { return }
        if let id = knownDIYPeripheralID,
           let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            diy = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
        }
        if let id = knownPeripheralID,
           let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            // A pending connect never times out: iOS completes it (waking the
            // app if needed) as soon as the scale starts advertising.
            scale = peripheral
            peripheral.delegate = self
            // Keep "Synced 07:12" on screen; only replace a transient state.
            if case .done = status {} else { status = .idle }
            appendLog("Pending connect to saved scale — step on it to sync")
            central.connect(peripheral)
        } else if knownDIYPeripheralID == nil {
            // Nothing paired yet: listen for either kind.
            startScan(for: [serviceUUID, wssUUID], timeout: nil)
        } else {
            startScan(for: [serviceUUID], timeout: nil)
        }
    }

    private func startScan(for services: [CBUUID], timeout: TimeInterval?) {
        scanStopWorkItem?.cancel()
        status = .scanning
        appendLog("Scanning for \(services.map(\.uuidString).joined(separator: ", "))…")
        central.scanForPeripherals(withServices: services)
        guard let timeout else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.central.stopScan()
            if case .scanning = self.status {
                self.status = self.lastSeen.values.max().map { .done($0) } ?? .idle
            }
            self.connectOrScan()
        }
        scanStopWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    /// Wait out the scale's own measurement sequence, then request the dump.
    private func scheduleMeasurementRequest(from peripheral: CBPeripheral) {
        syncWorkItem?.cancel()
        status = .syncing
        appendLog("Indications armed — letting the scale finish (\(Int(measurementSettleDelay))s)")
        let item = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral, peripheral.state == .connected else { return }
            self.requestMeasurements(from: peripheral)
        }
        syncWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + measurementSettleDelay, execute: item)
    }

    private func requestMeasurements(from peripheral: CBPeripheral) {
        // Whichever path got here (scheduled or manual), the request is no
        // longer pending — the disconnect handler relies on this to tell a
        // premature hang-up apart from a normal one.
        syncWorkItem?.cancel()
        syncWorkItem = nil
        guard let cmd = commandCharacteristic else {
            peripheral.discoverServices([serviceUUID])
            return
        }
        let payload = ScaleProtocol.timeSyncCommand(epoch: epoch)
        appendLog("→ time sync \(payload.map { String(format: "%02x", $0) }.joined(separator: ":"))")
        peripheral.writeValue(payload, for: cmd, type: .withResponse)
        status = .syncing
    }

    private func isDIY(_ peripheral: CBPeripheral) -> Bool {
        peripheral.identifier == diy?.identifier || peripheral.identifier == knownDIYPeripheralID
    }

    private func markSeen(_ kind: ScaleKind) {
        let now = Date()
        lastSeen[kind] = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "lastSeen.\(kind.rawValue)")
    }

    // MARK: - Data handling

    private func handleWeight(_ data: Data) {
        guard let p = ScaleProtocol.parseWeight(data, epoch: epoch) else {
            appendLog("⚠️ unparsed weight frame: \(hex(data))")
            return
        }
        appendLog("← weight \(String(format: "%.2f", p.weightKg)) kg  user \(p.userId.map(String.init) ?? "–")  \(p.date.formatted())")
        recordWeight(p.weightKg, date: p.date, scaleUserId: p.userId)
    }

    private func handleDIYWeight(_ data: Data) {
        guard let p = WeightScaleProtocol.parseMeasurement(data) else {
            appendLog("⚠️ unparsed 0x2A9D frame: \(hex(data))")
            return
        }
        appendLog("← DIY weight \(String(format: "%.2f", p.weightKg)) kg  user \(p.userId.map(String.init) ?? "–")")
        recordWeight(p.weightKg, date: p.date, scaleUserId: p.userId)
        markSeen(.diy)
    }

    /// Store a weight, falling back to matching by weight when the scale
    /// itself didn't recognise who was standing on it.
    private func recordWeight(_ weightKg: Double, date: Date, scaleUserId: Int?) {
        var slot = scaleUserId
        if scaleUserId == nil {
            let match = ProfileMatcher.match(weightKg: weightKg, lastWeights: lastWeightPerProfile())
            if let match {
                appendLog("   scale recognised no one — matched to profile \(match) by weight")
            } else {
                appendLog("   scale recognised no one — no single profile within \(Int(ProfileMatcher.toleranceKg)) kg, left unassigned")
            }
            unrecognizedThisSession.append(UnrecognizedWeighIn(weightKg: weightKg, slot: match, date: date))
            slot = match
        }
        let userId = slot ?? 0
        upsert(date: date, userId: userId) { m in
            m.weightKg = weightKg
        } create: {
            ScaleMeasurement(date: date, userId: userId, weightKg: weightKg)
        }
    }

    /// Most recent stored weight for each profile, guests included, so a
    /// returning guest lands on their own profile again.
    private func lastWeightPerProfile() -> [Int: Double] {
        MainActor.assumeIsolated {
            let descriptor = FetchDescriptor<ScaleMeasurement>(
                predicate: #Predicate { $0.userId > 0 && $0.weightKg > 0 },
                sortBy: [SortDescriptor(\.date, order: .reverse)])
            var latest: [Int: Double] = [:]
            for m in (try? modelContainer.mainContext.fetch(descriptor)) ?? [] where latest[m.userId] == nil {
                latest[m.userId] = m.weightKg
            }
            return latest
        }
    }

    /// End of a session: the unrecognised-weigh-in ping, or the receipt.
    private func reportSession() {
        let hadUnrecognized = unrecognizedThisSession.contains {
            $0.slot == nil && $0.date > Date().addingTimeInterval(-10 * 60)
        }
        reportUnrecognizedWeighIns()
        if !hadUnrecognized { postReceipt() }
    }

    /// One notification per session, for the newest unrecognised weigh-in.
    /// Older ones the scale re-sends from memory don't deserve a ping.
    private func reportUnrecognizedWeighIns() {
        defer { unrecognizedThisSession.removeAll() }
        guard let newest = unrecognizedThisSession.max(by: { $0.date < $1.date }),
              newest.date > Date().addingTimeInterval(-10 * 60) else { return }
        if let slot = newest.slot {
            RecognitionHelp.request(slot: slot)
        }
        ScaleNotifications.postUnrecognizedWeighIn(
            weightKg: newest.weightKg,
            slot: newest.slot,
            ownSlot: UserDefaults.standard.integer(forKey: "myUserSlot"))
    }

    /// The receipt for this phone's own newest reading from the last ten
    /// minutes, once, after Apple Health has it.
    private func postReceipt() {
        MainActor.assumeIsolated {
            let mySlot = UserDefaults.standard.integer(forKey: "myUserSlot")
            let since = Date().addingTimeInterval(-10 * 60)
            let firstGuest = Household.firstGuestSlot
            let descriptor = FetchDescriptor<ScaleMeasurement>(
                predicate: #Predicate { $0.weightKg > 0 && $0.date > since && $0.userId > 0 && $0.userId < firstGuest },
                sortBy: [SortDescriptor(\.date, order: .reverse)])
            let recent = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
            guard let newest = recent.first(where: { mySlot == 0 || $0.userId == mySlot }),
                  UserDefaults.standard.string(forKey: "lastReceiptKey") != newest.key else { return }
            UserDefaults.standard.set(newest.key, forKey: "lastReceiptKey")

            let slot = newest.userId, before = newest.date
            let previousDescriptor = FetchDescriptor<ScaleMeasurement>(
                predicate: #Predicate { $0.userId == slot && $0.weightKg > 0 && $0.date < before },
                sortBy: [SortDescriptor(\.date, order: .reverse)])
            let previous = (try? modelContainer.mainContext.fetch(previousDescriptor))?.first
            let change = previous.map { Say.change(from: $0, to: newest) }
            let weight = newest.weightKg

            health.pushUnsynced(container: modelContainer) { result in
                let inHealth: Bool
                switch result {
                case .saved, .nothingToDo: inHealth = true
                case .failed, .unavailable: inHealth = false
                }
                ScaleNotifications.postConfirmation(weightKg: weight, inHealth: inHealth, change: change)
            }
        }
    }

    #if DEBUG
    /// Runs an unrecognised weigh-in through the same path as a real one, to
    /// check matching, the notification and the dashboard cards in the simulator.
    func simulateUnrecognizedWeighIn(weightKg: Double) {
        appendLog("(debug) simulated unrecognised weigh-in \(weightKg) kg")
        recordWeight(weightKg, date: .now, scaleUserId: nil)
        reportUnrecognizedWeighIns()
    }

    /// A recognised weigh-in for this phone's profile, with composition, to
    /// see the Footprints moment and the receipt in the simulator.
    func simulateWeighIn(weightKg: Double) {
        let slot = max(1, UserDefaults.standard.integer(forKey: "myUserSlot"))
        appendLog("(debug) simulated weigh-in \(weightKg) kg for P\(slot)")
        let now = Date.now
        upsert(date: now, userId: slot) { m in
            m.weightKg = weightKg
        } create: {
            ScaleMeasurement(date: now, userId: slot, weightKg: weightKg,
                             fatPercent: 18.4, waterPercent: 57.9, musclePercent: 40.1,
                             boneKg: 3.4, kcal: 2637, source: "debug")
        }
        markSeen(.medisana)
        status = .done(now)
        postReceipt()
    }
    #endif

    private func handleComposition(_ data: Data) {
        guard let p = ScaleProtocol.parseComposition(data, epoch: epoch) else {
            appendLog("⚠️ no body composition in frame (scale matched no profile?): \(hex(data))")
            return
        }
        appendLog("← body comp fat \(p.fatPercent)% water \(p.waterPercent)% muscle \(p.musclePercent)%")
        upsert(date: p.date, userId: p.userId ?? 0) { m in
            m.fatPercent = p.fatPercent
            m.waterPercent = p.waterPercent
            m.musclePercent = p.musclePercent
            m.boneKg = p.boneKg
            m.kcal = p.kcal
        } create: {
            // Composition without a weight packet yet — store with weight 0;
            // the weight packet for the same minute will fill it in.
            let m = ScaleMeasurement(date: p.date, userId: p.userId ?? 0, weightKg: 0)
            m.fatPercent = p.fatPercent
            m.waterPercent = p.waterPercent
            m.musclePercent = p.musclePercent
            m.boneKg = p.boneKg
            m.kcal = p.kcal
            return m
        }
    }

    /// Insert or update the measurement matching (date-rounded-to-minute, user).
    private func upsert(date: Date, userId: Int,
                        update: (ScaleMeasurement) -> Void,
                        create: () -> ScaleMeasurement) {
        // Delegate callbacks run on the main queue (central uses queue: .main),
        // so it is safe to use the main context — this keeps @Query views live.
        // ModelContext is not Sendable, so it must stay inside the closure.
        MainActor.assumeIsolated {
            let context = modelContainer.mainContext
            let key = ScaleMeasurement.makeKey(date: date, userId: userId)
            let predicate = #Predicate<ScaleMeasurement> { $0.key == key }
            let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first

            if let m = existing {
                let hadData = m.weightKg > 0 && m.fatPercent != nil
                update(m)
                if !hadData { m.healthSynced = false }
            } else {
                context.insert(create())
                newReadingsThisSession += 1
            }
            try? context.save()

            // Push anything unsynced to Apple Health.
            health.pushUnsynced(container: modelContainer)
        }
    }

    // MARK: - Log

    func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.log.append(BLELogLine(text: text))
            if self.log.count > 400 { self.log.removeFirst(self.log.count - 400) }
        }
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

// MARK: - CBCentralManagerDelegate

extension ScaleManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            appendLog("Bluetooth on")
            connectOrScan()
        case .poweredOff:
            status = .bluetoothOff
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // App was relaunched in the background because a scale appeared.
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for p in peripherals {
            p.delegate = self
            if p.identifier == knownDIYPeripheralID {
                diy = p
            } else {
                scale = p
            }
            appendLog("Restored in background for \(p.name ?? "scale")")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        appendLog("Discovered \(peripheral.name ?? "unnamed") RSSI \(RSSI)")
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        central.stopScan()
        scanStopWorkItem?.cancel()
        peripheral.delegate = self
        if advertised.contains(wssUUID) {
            diy = peripheral
            knownDIYPeripheralID = peripheral.identifier
            isDIYPaired = true
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
            diyName = name
            UserDefaults.standard.set(name, forKey: "diyScaleName")
        } else {
            scale = peripheral
            knownPeripheralID = peripheral.identifier
            isPaired = true
        }
        status = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if isDIY(peripheral) {
            appendLog("Connected to DIY scale")
            status = .syncing
            peripheral.discoverServices([wssUUID, batteryServiceUUID])
            return
        }
        guard !sessionStarted else { return }
        sessionStarted = true
        appendLog("Connected to \(peripheral.name ?? "scale")")
        status = .syncing
        serviceDiscoveryRetries = 0
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        appendLog("Connect failed: \(error?.localizedDescription ?? "unknown")")
        if !isDIY(peripheral) { sessionStarted = false }
        connectOrScan()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        appendLog("Disconnected\(error.map { " (\($0.localizedDescription))" } ?? "")")
        if isDIY(peripheral) {
            reportSession()
            if case .syncing = status { status = .done(Date()) }
            if knownDIYPeripheralID != nil { central.connect(peripheral) }
            return
        }
        if syncWorkItem != nil {
            appendLog("⚠️ Scale hung up before we could request data — settle delay too long")
        }
        syncWorkItem?.cancel()
        syncWorkItem = nil
        commandCharacteristic = nil
        sessionStarted = false
        if newReadingsThisSession > 0 || !unrecognizedThisSession.isEmpty { markSeen(.medisana) }
        reportSession()
        if case .syncing = status { status = .done(Date()) }
        // Re-arm the pending connect so the next weigh-in wakes us again.
        if knownPeripheralID != nil { central.connect(peripheral) }
    }
}

// MARK: - CBPeripheralDelegate

extension ScaleManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            appendLog("Service discovery failed: \(error!.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        if isDIY(peripheral) {
            for service in services { peripheral.discoverCharacteristics(nil, for: service) }
            return
        }
        for service in services {
            appendLog("Service \(service.uuid)")
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
        if services.isEmpty {
            // Seen on the re-armed connection straight after a weigh-in. The
            // connection itself succeeds, so the scale is still reachable —
            // this is usually iOS handing back a stale/empty GATT cache rather
            // than a sleeping radio. Retry a couple of times before giving up;
            // if it recovers we can still collect the finished measurement.
            if serviceDiscoveryRetries < 2 {
                serviceDiscoveryRetries += 1
                appendLog("No services returned — retry \(serviceDiscoveryRetries)/2")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak peripheral] in
                    guard let peripheral, peripheral.state == .connected else { return }
                    peripheral.discoverServices([self.serviceUUID])
                }
            } else {
                appendLog("No services after retries — scale radio has gone to sleep")
            }
        } else if services.first(where: { $0.uuid == serviceUUID }) == nil {
            appendLog("⚠️ Scale service 0x78B2 not found — see Debug tab and README troubleshooting")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        if isDIY(peripheral) {
            for c in service.characteristics ?? [] {
                switch c.uuid {
                case wssMeasurementUUID:
                    peripheral.setNotifyValue(true, for: c)
                case batteryLevelUUID:
                    peripheral.readValue(for: c)
                    if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
                default:
                    break
                }
            }
            return
        }
        guard service.uuid == serviceUUID else { return }
        indicationsPending = 0
        for c in service.characteristics ?? [] {
            appendLog("Characteristic \(c.uuid) props \(c.properties.rawValue)")
            switch c.uuid {
            case featureUUID, weightUUID, personUUID:
                indicationsPending += 1
                peripheral.setNotifyValue(true, for: c)
            case commandUUID:
                commandCharacteristic = c
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("Indication enable failed for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        // The DIY scale indicates on its own once subscribed; nothing to ask for.
        if isDIY(peripheral) { return }
        indicationsPending -= 1
        // Once all three indications are armed, let the scale finish measuring
        // before asking for the dump. Anything it sends spontaneously in the
        // meantime still arrives via the indications we just enabled.
        if indicationsPending <= 0 {
            scheduleMeasurementRequest(from: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case weightUUID: handleWeight(data)
        case featureUUID: handleComposition(data)
        case personUUID: appendLog("← person frame: \(hex(data))")
        case wssMeasurementUUID: handleDIYWeight(data)
        case batteryLevelUUID: diyBattery = data.first.map(Int.init)
        default: appendLog("← \(characteristic.uuid): \(hex(data))")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("Write failed: \(error.localizedDescription)")
        } else {
            appendLog("Time sync accepted — receiving stored measurements")
        }
    }
}
