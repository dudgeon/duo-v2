import Foundation

/// Make a Project's interview (DL-223): once the starter _PROJECT.md is written, a new Claude session
/// in the folder is sent this as its first message, so Claude looks around, asks a few questions
/// and fills the file in. The message is the whole instruction, in the open: it stays in the
/// transcript, so a resumed session still knows what it was asked.
public enum ProjectInterview {
    public static func prompt(title: String) -> String {
        """
        Interview me about this project, \(title), so you can fill in its _PROJECT.md. \
        Look around this folder first, then ask me three to five short questions, one at a time, \
        only about what you can't tell from the files. \
        Then fill in _PROJECT.md: `goal` (one line) and `next` (the next step) in its properties, \
        a short Why, Done when as checkboxes, and one dated line under Log. \
        Keep its properties valid YAML, leave `status`, `health` and the rest of the file as they are, \
        and don't change any other file.
        """
    }
}
