import Foundation

struct FileOrbitItem: Identifiable, Equatable {
    let file: ChangedFile
    let rect: CGRect
    var id: String { file.id }
}
