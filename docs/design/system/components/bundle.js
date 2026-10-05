/* @ds-bundle: {"format":4,"namespace":"Duo","components":[]} */
// Duo is a native SwiftUI app: there is no web component library to mount. Each component's
// preview.html is a static recreation from the tokens, and its README says where it lives in
// Sources/DuoKit. This script only declares the namespace, so the previews run.
window.Duo = { native: true, source: "https://github.com/dudgeon/duo-v2/tree/HEAD/Sources/DuoKit" };
