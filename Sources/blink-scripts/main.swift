// Prints the JavaScript that BlinkCore injects into pages, as JSON, so the
// browser test can run exactly what ships. See Tests/Browser/run.sh.
import Foundation
import BlinkCore

let elements = [
    HiddenElement(host: "example.com", selector: "#sidebar"),
    HiddenElement(host: "www.example.com", selector: "div.promo > p:nth-of-type(2)"),
    HiddenElement(host: "other.org", selector: "main"),
]
let scripts: [String: String] = [
    "picker": ElementHiding.pickerScript,
    "stopPicker": ElementHiding.stopPickerScript,
    "hide": ElementHiding.userScript(for: elements),
    "hideNothing": ElementHiding.userScript(for: []),
    "scrollUnlock": ElementHiding.scrollUnlockScript,
]
let data = try JSONEncoder().encode(scripts)
FileHandle.standardOutput.write(data)
