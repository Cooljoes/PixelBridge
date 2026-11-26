import Foundation

struct CapabilityProfile: Decodable, Identifiable {
    let model: String
    let firmware: String?
    let blePairing, wifi, ptpip, jpeg, raw, video, uploadWhileOff, offsetResume: String
    var id: String { model }

    static func load(bundle: Bundle = .main) throws -> [CapabilityProfile] {
        guard let url = bundle.url(forResource: "NikonProfiles", withExtension: "json") else {
            throw CameraError.invalid("Camera profiles are missing.")
        }
        return try JSONDecoder().decode([CapabilityProfile].self, from: Data(contentsOf: url))
    }
}
