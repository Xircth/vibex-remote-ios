import Foundation

public struct PairingClient: Sendable {
    public static let clientProtocolVersion = "1.0"
    public static let protocolHeader = "x-vibex-protocol-version"

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func redeem(
        origin: HostOrigin,
        pairingToken: String,
        deviceName: String = "VibeX"
    ) async throws -> CompanionSession {
        guard !pairingToken.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PairingException("Pairing token is required")
        }
        let body = try JSONEncoder().encode(
            RedeemPairingRequest(pairing_token: pairingToken.trimmingCharacters(in: .whitespaces), device_name: deviceName)
        )
        let redeem = try await transport.execute(
            method: "POST",
            url: origin.resolve("/api/v1/auth/pairings/redeem"),
            headers: [
                "content-type": "application/json",
                Self.protocolHeader: Self.clientProtocolVersion,
            ],
            body: body
        )
        guard (200...299).contains(redeem.status) else {
            if [401, 403, 404, 409, 410].contains(redeem.status) {
                throw PairingException("请在电脑上再出示邀请")
            }
            throw PairingException("无法兑换连接码（\(redeem.status)）")
        }
        let credential = try JSONDecoder().decode(DeviceCredential.self, from: redeem.body)
        let extras = CompanionScopes.extras(credential.scopes)
        if !extras.isEmpty {
            throw PairingException("请在电脑上再出示邀请")
        }
        let capsExchange = try await transport.execute(
            method: "GET",
            url: origin.resolve("/api/v1/capabilities"),
            headers: [
                "authorization": "Bearer \(credential.access_token)",
                Self.protocolHeader: Self.clientProtocolVersion,
            ],
            body: nil
        )
        guard (200...299).contains(capsExchange.status) else {
            throw PairingException("Capabilities check failed (\(capsExchange.status))")
        }
        let capabilities = try JSONDecoder().decode(ServerCapabilities.self, from: capsExchange.body)
        guard let hostId = capabilities.host_id, !hostId.isEmpty else {
            throw PairingException("Host did not return host_id")
        }
        if protocolMajor(capabilities.protocol_version) != protocolMajor(Self.clientProtocolVersion) {
            throw PairingException("Protocol \(capabilities.protocol_version) is incompatible with \(Self.clientProtocolVersion)")
        }
        return CompanionSession(origin: origin, credential: credential, capabilities: capabilities)
    }
}
