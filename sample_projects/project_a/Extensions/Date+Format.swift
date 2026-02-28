import Foundation

extension Date {
    var taskFormat: String {
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: self)
    }
}
