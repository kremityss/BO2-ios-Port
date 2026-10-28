import Foundation

/// Browser MOVEMENT_SETTINGS values converted with the same 0.01 scale as Nuketown.
/// Data comes from movement-settings.js in the pinned Cloudflare deployment.
struct WebMovement {
    private let values: [String: Float]

    static let shared: WebMovement = {
        guard let url = Bundle.main.url(forResource: "MerkWebMovement", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["source"] as? String == "movement-settings.js",
              let raw = json["values"] as? [String: Any] else {
            return WebMovement(values: [:])
        }
        return WebMovement(values: raw.compactMapValues { ($0 as? NSNumber)?.floatValue })
    }()

    private func n(_ name: String, _ fallback: Float) -> Float {
        guard let value = values[name], value.isFinite, value >= 0 else { return fallback }
        return value
    }

    var walkSpeed: Float { n("walkSpeed", 3.0) }
    var sprintSpeed: Float { n("sprintSpeed", 4.5) }
    var tacticalSprintSpeed: Float { n("tacticalSprintSpeed", 5.05) }
    var crouchSpeed: Float { n("crouchSpeed", 1.7) }
    var groundAcceleration: Float { n("groundAcceleration", 36) }
    var groundDeceleration: Float { n("groundDeceleration", 32) }
    var airAcceleration: Float { n("airAcceleration", 14.5) }
    var slideSpeed: Float { n("slideSpeed", 4.85) }
    var slideDuration: Float { n("slideDuration", 0.62) }
    var slideCooldown: Float { n("slideCooldown", 0.16) }
    var slideFriction: Float { n("slideFriction", 1.05) }
    var slideMinSpeed: Float { n("slideMinSpeed", 2.85) }
    var slideExitSpeed: Float { n("slideExitSpeed", 2.05) }
    var slideHopBoost: Float { n("slideHopBoost", 1.025) }
    var gravity: Float { n("gravity", 10.5) }
    var jumpVelocity: Float { n("jumpVelocity", 3.3) }
    var coyoteTime: Float { n("coyoteTime", 0.1) }
    var jumpBufferTime: Float { n("jumpBufferTime", 0.12) }
    var maxAirSpeed: Float { n("maxAirSpeed", 4.65) }
}
