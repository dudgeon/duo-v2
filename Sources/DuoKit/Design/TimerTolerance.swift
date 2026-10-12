import Foundation

extension Timer {
    /// Lets the system fire this repeating timer up to 15 % late, so idle wake-ups can coalesce (C-79).
    @discardableResult func loose() -> Timer { tolerance = timeInterval * 0.15; return self }
}
