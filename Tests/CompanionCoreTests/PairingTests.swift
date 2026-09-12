import Testing
@testable import CompanionCore

@Test func parsesVibexPairingPayload() throws {
    let invitation = try PairingInvitationParser.parse(
        #"vibex-pairing:{"host_id":"h1","preset":"companion","pairing_token":"vbx_pair_abc","reachability":[{"origin":"http://192.168.1.8:3080","kind":"lan"},{"origin":"https://box.ts.net","kind":"tailscale"}]}"#
    )
    #expect(invitation.hostId == "h1")
    #expect(invitation.reachability.count == 2)
    #expect(invitation.reachability[1].origin.value == "https://box.ts.net")
}

@Test func dropsLoopbackOrigins() throws {
    let invitation = try PairingInvitationParser.parse(
        #"{"pairing_token":"tok","reachability":[{"origin":"http://127.0.0.1:3080","kind":"lan"},{"origin":"http://10.0.0.2:3080","kind":"lan"}]}"#
    )
    #expect(invitation.reachability.map(\.origin.value) == ["http://10.0.0.2:3080"])
}

@Test func parsesHostUrlsPayload() throws {
    let invitation = try PairingInvitationParser.parse(
        #"vibex-pairing:{"version":1,"pairing_token":"vbx_pair_x","preset":"companion","host_urls":["http://127.0.0.1:3080","http://192.168.1.20:3080"]}"#
    )
    #expect(invitation.reachability.map(\.origin.value) == ["http://192.168.1.20:3080"])
}

@Test func rejectsNonInvitation() {
    #expect(throws: PairingException.self) {
        try PairingInvitationParser.parse("http://192.168.1.1:3080")
    }
}

@Test func scanRejectsDeviceToken() {
    #expect(throws: PairingException.self) {
        try PairingInvitationParser.parse(#"{"pairing_token":"vbx_device_secret","reachability":[{"origin":"http://10.0.0.2:3080","kind":"lan"}]}"#)
    }
}

@Test func manualRejectsDeviceToken() {
    #expect(throws: PairingException.self) {
        try PairingInvitationParser.parseManual(origin: "http://10.0.0.2:3080", pairingToken: "vbx_device_secret")
    }
}

@Test func originOrderPrefersLastSuccessThenHttps() throws {
    let targets = [
        ReachabilityTarget(origin: try HostOrigin.parse("http://10.0.0.2:3080"), kind: "lan"),
        ReachabilityTarget(origin: try HostOrigin.parse("https://box.ts.net"), kind: "tailscale"),
    ]
    let order = OriginOrder.probeOrder(targets: targets, lastSuccess: "http://10.0.0.2:3080").map(\.value)
    #expect(order.first == "http://10.0.0.2:3080")
    #expect(order.contains("https://box.ts.net"))
}

@Test func originOrderPrefersPublishedHttpBeforeLan() throws {
    let targets = [
        ReachabilityTarget(origin: try HostOrigin.parse("http://192.168.1.20:17891"), kind: "lan"),
        ReachabilityTarget(origin: try HostOrigin.parse("http://47.109.140.92:13630"), kind: "published"),
    ]
    #expect(OriginOrder.probeOrder(targets: targets, lastSuccess: nil).map(\.value) == [
        "http://47.109.140.92:13630", "http://192.168.1.20:17891",
    ])
}

@Test func parsesPublicHttpIpWithoutScheme() throws {
    #expect(try HostOrigin.parse("47.109.140.92:13630").value == "http://47.109.140.92:13630")
    #expect(try HostOrigin.parse("http://47.109.140.92:13630/").value == "http://47.109.140.92:13630")
}

@Test func atsBlocksPublicHTTP() throws {
    #expect(try HostOrigin.parse("http://47.109.140.92:13630").isATSBlockedPublicHTTP)
    #expect(try HostOrigin.parse("http://192.168.1.20:17891").isATSBlockedPublicHTTP == false)
}

@Test func companionScopesExtras() {
    #expect(CompanionScopes.extras(["conversation.read"]).isEmpty)
    #expect(CompanionScopes.extras(["conversation.read", "plugin.write"]) == ["plugin.write"])
}

@Test func connectionWritesOnlyOnline() {
    #expect(ConnectionState.online.allowsWrites)
    #expect(!ConnectionState.offline.allowsWrites)
    #expect(!ConnectionState.recovering.allowsWrites)
}
