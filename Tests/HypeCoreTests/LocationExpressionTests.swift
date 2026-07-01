import Testing
import Foundation
@testable import HypeCore

// MARK: - Test infrastructure

/// A minimal `ScriptRuntimeProviding` conformer that injects a
/// controllable location result. All other protocol requirements get
/// default no-op implementations from the protocol extension.
private final class LocationTestRuntime: ScriptRuntimeProviding, @unchecked Sendable {
    private let lock = NSLock()

    // Configurable location outcome.
    private let _locationResult: LocationResult
    // Optional per-call sequence; the final element repeats once exhausted.
    private var _sequence: [LocationResult]
    private var _seqIndex: Int = 0
    private var _lastReason: String = ""

    enum LocationResult {
        case success(DeviceCoordinate)
        case denied
        case unavailable
    }

    init(result: LocationResult = .unavailable) {
        self._locationResult = result
        self._sequence = []
    }

    /// Returns each result in order across successive calls, repeating the
    /// last element once the sequence is exhausted. Lets a single script
    /// exercise e.g. "first call denied, second call succeeds".
    init(sequence: [LocationResult]) {
        self._locationResult = sequence.last ?? .unavailable
        self._sequence = sequence
    }

    // MARK: - Location (the two methods not covered by default impls)

    func currentDeviceLocation() async -> DeviceCoordinate? {
        let outcome: LocationResult = lock.withLock {
            guard !_sequence.isEmpty else { return _locationResult }
            let idx = min(_seqIndex, _sequence.count - 1)
            _seqIndex += 1
            return _sequence[idx]
        }
        switch outcome {
        case .success(let coord):
            lock.withLock { _lastReason = "" }
            return coord
        case .denied:
            lock.withLock { _lastReason = "location access denied" }
            return nil
        case .unavailable:
            lock.withLock { _lastReason = "location unavailable" }
            return nil
        }
    }

    func lastLocationFailureReason() async -> String {
        lock.withLock { _lastReason }
    }

    // MARK: - Required protocol stubs (not covered by default impls)

    func sleep(seconds: TimeInterval) async throws {}

    func navigateToCard(_ cardId: UUID) async {}

    func publishDocument(_ document: HypeDocument) async {}

    func enqueueMessage(
        _ message: String,
        params: [Value],
        targetId: UUID,
        currentCardId: UUID,
        mouseX: Double,
        mouseY: Double,
        scriptContext: ScriptDispatchContext?
    ) async {}

    func startAIRequest(prompt: String, model: String?,
                        callbackMessage: String,
                        owner: RuntimeOwnerContext) async throws -> UUID { UUID() }

    func startMeshyRequest(prompt: String, style: String?, model: String?,
                           callbackMessage: String,
                           owner: RuntimeOwnerContext) async throws -> UUID { UUID() }

    func startRemeshRequest(sourceAssetName: String, targetPolycount: Int,
                            callbackMessage: String,
                            owner: RuntimeOwnerContext) async throws -> UUID { UUID() }

    func startRetextureRequest(sourceAssetName: String, stylePrompt: String,
                               callbackMessage: String,
                               owner: RuntimeOwnerContext) async throws -> UUID { UUID() }

    func setSpeechListenerActive(_ active: Bool, owner: RuntimeOwnerContext) async throws {}

    func isSpeechListenerActive() async -> Bool { false }

    func startHTTPRequest(_ spec: OutboundHTTPRequestSpec,
                          owner: RuntimeOwnerContext) async throws -> UUID { UUID() }

    func reply(to requestID: UUID, status: Int, headersText: String, body: String) async throws {}

    func startListener(_ spec: ListenerSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }

    func connectTCP(_ spec: TCPConnectionSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }

    func send(_ data: String, toConnection id: UUID) async throws {}

    func closeConnection(_ id: UUID) async {}

    func stopListener(_ id: UUID) async {}

    func runtimeProperty(objectType: String, id: UUID, property: String,
                         argument: String?) async -> String { "" }

    func pushCardToHistory(_ cardId: UUID) async {}

    func popCardFromHistory() async -> UUID? { nil }

    func recentCards() async -> String { "" }

    func setFoundState(_ state: FoundState?) async {}
    func foundState() async -> FoundState? { nil }

    func setSelectedState(_ state: SelectedState?) async {}
    func selectedState() async -> SelectedState? { nil }

    func setClickState(_ state: ClickState) async {}
    func clickState() async -> ClickState? { nil }
}

// MARK: - Shared test document helpers

/// San Francisco coordinate for "success" tests.
private let sfCoord = DeviceCoordinate(latitude: 37.7749, longitude: -122.4194)

/// Build a document with a button, two output fields, and a map part.
private func makeLocationDoc() -> (doc: HypeDocument, cardId: UUID, btnId: UUID) {
    var doc = HypeDocument.newDocument(name: "LocationTest")
    let cardId = doc.cards[0].id

    var btn = Part(partType: .button, cardId: cardId, name: "TestBtn",
                   left: 0, top: 0, width: 80, height: 30)
    btn.script = ""
    doc.addPart(btn)

    var outField = Part(partType: .field, cardId: cardId, name: "out",
                        left: 0, top: 40, width: 200, height: 30)
    outField.textContent = ""
    doc.addPart(outField)

    var rField = Part(partType: .field, cardId: cardId, name: "r",
                      left: 0, top: 80, width: 200, height: 30)
    rField.textContent = ""
    doc.addPart(rField)

    var latField = Part(partType: .field, cardId: cardId, name: "lat",
                        left: 0, top: 120, width: 200, height: 30)
    latField.textContent = ""
    doc.addPart(latField)

    var lonField = Part(partType: .field, cardId: cardId, name: "lon",
                        left: 0, top: 160, width: 200, height: 30)
    lonField.textContent = ""
    doc.addPart(lonField)

    var mapPart = Part(partType: .map, cardId: cardId, name: "homeMap",
                       left: 0, top: 200, width: 300, height: 200)
    mapPart.mapCenterLat = 37.7749
    mapPart.mapCenterLon = -122.4194
    mapPart.mapSpan = 0.05
    mapPart.mapLocation = ""
    doc.addPart(mapPart)

    return (doc, cardId, btn.id)
}

/// Dispatch a script against the given button, optionally injecting a runtime provider.
private func run(
    _ script: String,
    doc: HypeDocument,
    cardId: UUID,
    btnId: UUID,
    runtime: (any ScriptRuntimeProviding)? = nil
) async -> ExecutionResult {
    var d = doc
    d.updatePart(id: btnId) { $0.script = script }
    let dispatcher = MessageDispatcher()
    let snapshot = d
    return await runOnLargeStack { [snapshot, runtime] in
        dispatcher.dispatch(
            message: "mouseUp",
            params: [],
            targetId: btnId,
            document: snapshot,
            currentCardId: cardId,
            runtimeProvider: runtime
        )
    }
}

/// Get a named field's text from a result.
private func field(_ result: ExecutionResult, name: String) -> String? {
    result.modifiedDocument?.parts.first { $0.name == name }?.textContent
}

/// Get a named map part from a result.
private func mapPart(_ result: ExecutionResult, name: String) -> Part? {
    result.modifiedDocument?.parts.first { $0.name == name && $0.partType == .map }
}

// MARK: - Test suite

@Suite("LocationExpression — user location + map put", .serialized)
struct LocationExpressionTests {

    // MARK: §1 — put user location into field "out"

    @Test("put user location into field — success runtime returns lat,lon")
    func myLocationPutIntoField() async {
        let (doc, cardId, btnId) = makeLocationDoc()
        let rt = LocationTestRuntime(result: .success(sfCoord))

        let result = await run("""
        on mouseUp
          put user location into field "out"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: rt)

        #expect(field(result, name: "out") == "37.7749,-122.4194")
    }

    // MARK: §2 — get user location then put it

    @Test("get user location then put it into field")
    func myLocationGetThenPut() async {
        let (doc, cardId, btnId) = makeLocationDoc()
        let rt = LocationTestRuntime(result: .success(sfCoord))

        let result = await run("""
        on mouseUp
          get user location
          put it into field "out"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: rt)

        #expect(field(result, name: "out") == "37.7749,-122.4194")
    }

    // MARK: §3 — item 1 / item 2 of user location

    @Test("item 1 of user location == lat; item 2 == lon")
    func myLocationItems() async {
        let (doc, cardId, btnId) = makeLocationDoc()
        let rt = LocationTestRuntime(result: .success(sfCoord))

        let result = await run("""
        on mouseUp
          put item 1 of user location into field "lat"
          put item 2 of user location into field "lon"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: rt)

        #expect(field(result, name: "lat") == "37.7749")
        #expect(field(result, name: "lon") == "-122.4194")
    }

    // MARK: §4 — put user location into map centers the map

    @Test("put user location into map recenters, preserves span")
    func myLocationPutIntoMap() async {
        let (doc, cardId, btnId) = makeLocationDoc()
        let rt = LocationTestRuntime(result: .success(sfCoord))

        let result = await run("""
        on mouseUp
          put user location into map "homeMap"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: rt)

        let m = mapPart(result, name: "homeMap")
        #expect(m?.mapCenterLat == 37.7749)
        #expect(m?.mapCenterLon == -122.4194)
        // Span is preserved — the initial 0.05 must not change.
        #expect(m?.mapSpan == 0.05)
        // mapLocation cleared when a coordinate is applied.
        #expect(m?.mapLocation == "")
    }

    // MARK: §5 — Denied runtime

    @Test("denied runtime: user location == empty, the result == reason")
    func myLocationDenied() async {
        let (doc, cardId, btnId) = makeLocationDoc()
        let rt = LocationTestRuntime(result: .denied)

        let result = await run("""
        on mouseUp
          put user location into field "out"
          put the result into field "r"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: rt)

        #expect(field(result, name: "out") == "")
        #expect(field(result, name: "r") == "location access denied")
    }

    // MARK: §6 — No provider

    @Test("nil runtime provider: user location == empty string")
    func myLocationNoProvider() async {
        let (doc, cardId, btnId) = makeLocationDoc()

        let result = await run("""
        on mouseUp
          put user location into field "out"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: nil)

        #expect(field(result, name: "out") == "")
    }

    // MARK: §7 — put "lat,lon" literal into map (no provider)

    @Test("put literal lat,lon string into map centers map")
    func putCoordLiteralIntoMap() async {
        let (doc, cardId, btnId) = makeLocationDoc()

        let result = await run("""
        on mouseUp
          put "40.0,-70.0" into map "homeMap"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: nil)

        let m = mapPart(result, name: "homeMap")
        #expect(m?.mapCenterLat == 40.0)
        #expect(m?.mapCenterLon == -70.0)
        #expect(m?.mapLocation == "")
    }

    // MARK: §8 — put place name into map

    @Test("put place name into map sets mapLocation, leaves center unchanged")
    func putPlaceNameIntoMap() async {
        let (doc, cardId, btnId) = makeLocationDoc()

        let result = await run("""
        on mouseUp
          put "Paris" into map "homeMap"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: nil)

        let m = mapPart(result, name: "homeMap")
        #expect(m?.mapLocation == "Paris")
        // Center must be unchanged from the initial values.
        #expect(m?.mapCenterLat == 37.7749)
        #expect(m?.mapCenterLon == -122.4194)
    }

    // MARK: §9 — put empty into map clears mapLocation

    @Test("put empty string into map clears mapLocation")
    func putEmptyIntoMapClearsLocation() async {
        var (doc, cardId, btnId) = makeLocationDoc()
        // Pre-set a non-empty mapLocation.
        if let idx = doc.parts.firstIndex(where: { $0.name == "homeMap" }) {
            doc.parts[idx].mapLocation = "Tokyo"
        }

        let result = await run("""
        on mouseUp
          put "" into map "homeMap"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: nil)

        let m = mapPart(result, name: "homeMap")
        #expect(m?.mapLocation == "")
    }

    // MARK: §10 — put out-of-range coord falls back to mapLocation

    @Test("put out-of-range coord string sets mapLocation, not center")
    func putOutOfRangeCoordFallsBack() async {
        let (doc, cardId, btnId) = makeLocationDoc()

        let result = await run("""
        on mouseUp
          put "999,999" into map "homeMap"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: nil)

        let m = mapPart(result, name: "homeMap")
        // "999,999" is not a valid WGS-84 coordinate → geocode path.
        #expect(m?.mapLocation == "999,999")
        // Center must be unchanged.
        #expect(m?.mapCenterLat == 37.7749)
        #expect(m?.mapCenterLon == -122.4194)
    }

    // MARK: §11 — showsUserLocation get/set

    @Test("showsUserLocation default false; set to true round-trips")
    func showsUserLocationProperty() async {
        let (doc, cardId, btnId) = makeLocationDoc()

        // Default should be false.
        let result1 = await run("""
        on mouseUp
          put the showsUserLocation of map "homeMap" into field "out"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: nil)
        #expect(field(result1, name: "out") == "false")

        // Set to true, then read back.
        let result2 = await run("""
        on mouseUp
          set the showsUserLocation of map "homeMap" to true
          put the showsUserLocation of map "homeMap" into field "out"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: nil)
        #expect(field(result2, name: "out") == "true")
    }

    // MARK: §12 — successful read clears a stale `the result`

    @Test("successful user location clears a prior failure reason in the result")
    func userLocationClearsResultOnSuccess() async {
        let (doc, cardId, btnId) = makeLocationDoc()
        // First call denied (sets the result), second call succeeds (must clear it).
        let rt = LocationTestRuntime(sequence: [.denied, .success(sfCoord)])

        let result = await run("""
        on mouseUp
          put user location into field "out"
          put the result into field "r"
          put user location into field "lat"
          put the result into field "lon"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: rt)

        #expect(field(result, name: "r") == "location access denied")
        #expect(field(result, name: "lat") == "37.7749,-122.4194")
        // The successful second read must have cleared the stale reason.
        #expect(field(result, name: "lon") == "")
    }

    // MARK: §13 — `the user location` article form

    @Test("the user location (article form) returns lat,lon")
    func theUserLocationArticleForm() async {
        let (doc, cardId, btnId) = makeLocationDoc()
        let rt = LocationTestRuntime(result: .success(sfCoord))

        let result = await run("""
        on mouseUp
          put the user location into field "out"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: rt)

        #expect(field(result, name: "out") == "37.7749,-122.4194")
    }

    @Test("put the user location into map centers (article form)")
    func theUserLocationIntoMap() async {
        let (doc, cardId, btnId) = makeLocationDoc()
        let rt = LocationTestRuntime(result: .success(sfCoord))

        let result = await run("""
        on mouseUp
          put the user location into map "homeMap"
        end mouseUp
        """, doc: doc, cardId: cardId, btnId: btnId, runtime: rt)

        let m = mapPart(result, name: "homeMap")
        #expect(m?.mapCenterLat == 37.7749)
        #expect(m?.mapCenterLon == -122.4194)
    }
}

// MARK: - Parser tests

@Suite("Parser — user location forms", .serialized)
struct UserLocationParserTests {

    private func parse(_ source: String) -> Bool {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return (try? parser.parse()) != nil
    }

    @Test("put user location into map parses")
    func parseMyLocationIntoMap() {
        #expect(parse("on t\n  put user location into map \"m\"\nend t"))
    }

    @Test("put user location into variable parses")
    func parseMyLocationIntoVar() {
        #expect(parse("on t\n  put user location into x\nend t"))
    }

    @Test("get user location parses")
    func parseGetMyLocation() {
        #expect(parse("on t\n  get user location\nend t"))
    }

    @Test("bare 'user' as identifier still parses when not followed by location")
    func parseBareUserIdentifier() {
        // 'user' alone (the special prefix) must fall through to a variable
        // reference when 'location' does not follow.
        #expect(parse("on t\n  put user into x\nend t"))
    }

    @Test("item 1 of user location parses")
    func parseItemOfMyLocation() {
        #expect(parse("on t\n  put item 1 of user location into x\nend t"))
    }

    @Test("the user location (article form) parses")
    func parseTheUserLocation() {
        #expect(parse("on t\n  put the user location into x\nend t"))
    }

    @Test("put the user location into map parses")
    func parseTheUserLocationIntoMap() {
        #expect(parse("on t\n  put the user location into map \"m\"\nend t"))
    }
}

// MARK: - Codable round-trip tests

@Suite("Part.mapShowsUserLocation persistence", .serialized)
struct MapShowsUserLocationCodableTests {

    @Test("Part without mapShowsUserLocation key decodes to false")
    func decodesMissingKeyAsFalse() throws {
        var part = Part(partType: .map, cardId: UUID(), name: "m")
        part.mapShowsUserLocation = true  // will be stripped by re-encoding via omit

        // Encode to JSON and strip the mapShowsUserLocation key.
        let encoder = JSONEncoder()
        var dict = try JSONSerialization.jsonObject(with: try encoder.encode(part)) as! [String: Any]
        dict.removeValue(forKey: "mapShowsUserLocation")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(Part.self, from: strippedData)
        #expect(decoded.mapShowsUserLocation == false)
    }

    @Test("Part with mapShowsUserLocation true round-trips to true")
    func roundTripsTrue() throws {
        var part = Part(partType: .map, cardId: UUID(), name: "m")
        part.mapShowsUserLocation = true

        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.mapShowsUserLocation == true)
    }

    @Test("Part with mapShowsUserLocation false round-trips to false")
    func roundTripsFalse() throws {
        var part = Part(partType: .map, cardId: UUID(), name: "m")
        part.mapShowsUserLocation = false

        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.mapShowsUserLocation == false)
    }
}

// MARK: - DeviceCoordinate unit tests

@Suite("DeviceCoordinate", .serialized)
struct DeviceCoordinateTests {

    // MARK: Validation — rejection cases

    @Test("validated rejects latitude > 90")
    func rejectsLatOver90() {
        #expect(DeviceCoordinate.validated(latitude: 91, longitude: 0) == nil)
    }

    @Test("validated rejects latitude < -90")
    func rejectsLatUnder90() {
        #expect(DeviceCoordinate.validated(latitude: -91, longitude: 0) == nil)
    }

    @Test("validated rejects longitude > 180")
    func rejectsLonOver180() {
        #expect(DeviceCoordinate.validated(latitude: 0, longitude: 181) == nil)
    }

    @Test("validated rejects longitude < -180")
    func rejectsLonUnder180() {
        #expect(DeviceCoordinate.validated(latitude: 0, longitude: -181) == nil)
    }

    @Test("validated rejects NaN latitude")
    func rejectsNaNLat() {
        #expect(DeviceCoordinate.validated(latitude: Double.nan, longitude: 0) == nil)
    }

    @Test("validated rejects NaN longitude")
    func rejectsNaNLon() {
        #expect(DeviceCoordinate.validated(latitude: 0, longitude: Double.nan) == nil)
    }

    @Test("validated rejects +inf latitude")
    func rejectsInfLat() {
        #expect(DeviceCoordinate.validated(latitude: Double.infinity, longitude: 0) == nil)
    }

    @Test("validated rejects -inf longitude")
    func rejectsNegInfLon() {
        #expect(DeviceCoordinate.validated(latitude: 0, longitude: -Double.infinity) == nil)
    }

    // MARK: Validation — acceptance cases

    @Test("validated accepts lat 90 (north pole)")
    func acceptsLat90() {
        #expect(DeviceCoordinate.validated(latitude: 90, longitude: 0) != nil)
    }

    @Test("validated accepts lat -90 (south pole)")
    func acceptsLatMinus90() {
        #expect(DeviceCoordinate.validated(latitude: -90, longitude: 0) != nil)
    }

    @Test("validated accepts lon 180")
    func acceptsLon180() {
        #expect(DeviceCoordinate.validated(latitude: 0, longitude: 180) != nil)
    }

    @Test("validated accepts lon -180")
    func acceptsLonMinus180() {
        #expect(DeviceCoordinate.validated(latitude: 0, longitude: -180) != nil)
    }

    // MARK: hypeTalkString

    @Test("hypeTalkString contains exactly one comma")
    func hypeTalkStringHasOneComma() {
        let coord = DeviceCoordinate(latitude: 37.7749, longitude: -122.4194)
        let s = coord.hypeTalkString
        #expect(s.filter { $0 == "," }.count == 1)
    }

    @Test("hypeTalkString splits back to lat and lon")
    func hypeTalkStringRoundTrips() {
        let coord = DeviceCoordinate(latitude: 37.7749, longitude: -122.4194)
        let parts = coord.hypeTalkString.split(separator: ",")
        #expect(parts.count == 2)
        #expect(Double(parts[0]) == 37.7749)
        #expect(Double(parts[1]) == -122.4194)
    }

    @Test("hypeTalkString is locale-independent (always uses '.' not ',')")
    func hypeTalkStringLocaleIndependent() {
        let coord = DeviceCoordinate(latitude: 51.5, longitude: 0.1278)
        let s = coord.hypeTalkString
        // Must contain exactly one comma (the item delimiter), never more.
        #expect(s.filter { $0 == "," }.count == 1)
        // The decimal point must be '.', not a locale-specific separator.
        // Split on comma and check each part doesn't contain a second comma.
        let components = s.split(separator: ",")
        #expect(components.count == 2)
        for c in components {
            #expect(!c.contains(","))
        }
    }

    @Test("hypeTalkString for whole-number coordinates omits decimal point")
    func hypeTalkStringWholeNumber() {
        let coord = DeviceCoordinate(latitude: 40.0, longitude: -70.0)
        let s = coord.hypeTalkString
        // Should produce "40,-70" not "40.0,-70.0"
        #expect(s == "40,-70")
    }

    // MARK: Property / invariant tests

    @Test("validated is total over a range of finite doubles")
    func validatedTotalOverFinite() {
        // A broad range of valid and invalid doubles — validated must never crash.
        let lats: [Double] = [-91, -90, -45, 0, 45, 90, 91]
        let lons: [Double] = [-181, -180, -90, 0, 90, 180, 181]
        for lat in lats {
            for lon in lons {
                // Just ensure no crash.
                _ = DeviceCoordinate.validated(latitude: lat, longitude: lon)
            }
        }
    }

    @Test("validated never crashes on NaN or infinity inputs")
    func validatedNeverCrashesOnSpecialValues() {
        let specials: [Double] = [Double.nan, Double.infinity, -Double.infinity]
        for v in specials {
            _ = DeviceCoordinate.validated(latitude: v, longitude: 0)
            _ = DeviceCoordinate.validated(latitude: 0, longitude: v)
            _ = DeviceCoordinate.validated(latitude: v, longitude: v)
        }
    }

    @Test("hypeTalkString split count always == 2 for validated coordinates")
    func hypeTalkStringSplitAlways2() {
        let samples: [(Double, Double)] = [
            (0, 0), (90, 180), (-90, -180), (37.7749, -122.4194),
            (51.5074, -0.1278), (-33.8688, 151.2093)
        ]
        for (lat, lon) in samples {
            guard let coord = DeviceCoordinate.validated(latitude: lat, longitude: lon) else {
                continue
            }
            let parts = coord.hypeTalkString.split(separator: ",")
            #expect(parts.count == 2,
                    "Expected 2 components for (\(lat),\(lon)), got \(parts.count)")
        }
    }

    @Test("validated result is in WGS-84 range when non-nil")
    func validatedResultAlwaysInRange() {
        let lats: [Double] = stride(from: -90.0, through: 90.0, by: 30.0).map { $0 }
        let lons: [Double] = stride(from: -180.0, through: 180.0, by: 60.0).map { $0 }
        for lat in lats {
            for lon in lons {
                if let c = DeviceCoordinate.validated(latitude: lat, longitude: lon) {
                    #expect(c.latitude >= -90 && c.latitude <= 90)
                    #expect(c.longitude >= -180 && c.longitude <= 180)
                }
            }
        }
    }
}
