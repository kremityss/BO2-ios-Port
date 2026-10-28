import Foundation

/// A level is only offered in the native picker after its actual published
/// visual mesh, authoritative collision and spawn data are all built.
enum NativeLevel: String, CaseIterable {
    case nuketown = "nuketown_2020"
    case hijacked = "hijacked"

    static var selected: NativeLevel {
        let stored=UserDefaults.standard.string(forKey:"merk.level") ?? ""
        return NativeLevel(rawValue:stored) ?? .nuketown
    }
    static func choose(_ level:NativeLevel) {
        UserDefaults.standard.set(level.rawValue,forKey:"merk.level")
    }
    var mapID:String {
        switch self {
        case .nuketown: return "mp_nuketown_2020"
        case .hijacked: return "mp_hijacked"
        }
    }
    var displayName:String {
        switch self {
        case .nuketown: return "NUKETOWN 2025"
        case .hijacked: return "HIJACKED"
        }
    }
    func resource(_ base:String)->String {
        self == .nuketown ? base : base + "Hijacked"
    }
    var isBundled:Bool {
        Bundle.main.url(forResource:resource("MerkMap"),withExtension:"meshbin") != nil &&
        Bundle.main.url(forResource:resource("MerkCollision"),withExtension:"bin") != nil &&
        Bundle.main.url(forResource:resource("MerkWebSpawns"),withExtension:"json") != nil
    }
}