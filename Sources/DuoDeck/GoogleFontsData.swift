/// A short list of common Google Fonts families (open licences, free to use in Google Slides), so
/// `deck template inventory` can flag a template font Google lacks (DL-268).
///
/// How this list was built: by hand, from the families that are most used on Google Fonts and in
/// slide templates, plus the metric-compatible families Google ships for the common Office fonts
/// (Arimo, Tinos, Cousine, Carlito, Caladea). It is not downloaded and not complete: a family missing
/// here is reported as "not in the common Google Fonts list", never as a certainty. Extend the array
/// when a real template turns up a miss. Names are compared case-insensitively.
enum GoogleFontsData {
    static let families: [String] = [
        "ABeeZee", "Abel", "Abril Fatface", "Alegreya", "Alegreya Sans", "Alfa Slab One", "Amatic SC", "Anton", "Archivo", "Archivo Black",
        "Archivo Narrow", "Arimo", "Arvo", "Asap", "Assistant", "Barlow", "Barlow Condensed", "Barlow Semi Condensed", "Bebas Neue",
        "Bitter", "Bree Serif", "Cabin", "Cairo", "Caladea", "Cardo", "Carlito", "Catamaran", "Caveat", "Chivo", "Cinzel", "Comfortaa",
        "Cormorant", "Cormorant Garamond", "Courier Prime", "Cousine", "Crimson Pro", "Crimson Text", "DM Mono", "DM Sans", "DM Serif Display",
        "DM Serif Text", "Dancing Script", "Domine", "EB Garamond", "Exo 2", "Fira Code", "Fira Mono", "Fira Sans", "Fira Sans Condensed",
        "Fjalla One", "Fredoka", "Frank Ruhl Libre", "Gelasio", "Gothic A1", "Grand Hotel", "Heebo", "Hind", "IBM Plex Mono", "IBM Plex Sans",
        "IBM Plex Sans Condensed", "IBM Plex Serif", "Inconsolata", "Indie Flower", "Inter", "Inter Tight", "Josefin Sans", "Josefin Slab",
        "Jost", "Kanit", "Karla", "Lato", "League Spartan", "Lexend", "Libre Baskerville", "Libre Franklin", "Lilita One", "Lobster",
        "Lora", "Manrope", "Marcellus", "Maven Pro", "Merriweather", "Merriweather Sans", "Montserrat", "Montserrat Alternates", "Mukta",
        "Mulish", "Noticia Text", "Noto Sans", "Noto Sans JP", "Noto Sans KR", "Noto Sans Mono", "Noto Sans SC", "Noto Sans TC", "Noto Serif",
        "Noto Serif JP", "Nunito", "Nunito Sans", "Old Standard TT", "Open Sans", "Oswald", "Outfit", "Overpass", "Oxygen", "PT Sans",
        "PT Sans Narrow", "PT Serif", "Pacifico", "Passion One", "Permanent Marker", "Philosopher", "Playfair Display", "Plus Jakarta Sans",
        "Poppins", "Prata", "Prompt", "Public Sans", "Quicksand", "Raleway", "Red Hat Display", "Red Hat Text", "Roboto", "Roboto Condensed",
        "Roboto Flex", "Roboto Mono", "Roboto Slab", "Rubik", "Sarabun", "Satisfy", "Sen", "Signika", "Slabo 27px", "Source Code Pro",
        "Source Sans 3", "Source Sans Pro", "Source Serif 4", "Source Serif Pro", "Space Grotesk", "Space Mono", "Spectral", "Syne",
        "Tajawal", "Teko", "Tinos", "Titillium Web", "Ubuntu", "Ubuntu Mono", "Unbounded", "Urbanist", "Varela Round", "Vollkorn", "Work Sans",
        "Yanone Kaffeesatz", "Zilla Slab",
    ]

    /// Where an Office or system font has a close Google equivalent: the substitute to suggest.
    static let substitutes: [String: String] = [
        "avenir next": "Nunito Sans", "avenir": "Nunito Sans", "calibri": "Carlito", "calibri light": "Carlito", "cambria": "Caladea",
        "arial": "Arimo", "helvetica": "Arimo", "helvetica neue": "Inter", "times new roman": "Tinos", "courier new": "Cousine",
        "segoe ui": "Open Sans", "tahoma": "Open Sans", "verdana": "Open Sans", "trebuchet ms": "Fira Sans", "georgia": "Gelasio",
        "gill sans": "Lato", "gill sans mt": "Lato", "futura": "Jost", "century gothic": "Poppins", "garamond": "EB Garamond",
        "palatino": "Lora", "book antiqua": "Lora", "franklin gothic": "Libre Franklin", "sf pro": "Inter", "sf pro text": "Inter",
        "sf pro display": "Inter", "-apple-system": "Inter", "aptos": "Inter", "aptos display": "Inter", "consolas": "Inconsolata",
        "menlo": "Roboto Mono", "monaco": "Roboto Mono",
    ]

    static func isGoogle(_ family: String) -> Bool {
        let f = family.lowercased()
        return families.contains { $0.lowercased() == f }
    }

    static func substitute(for family: String) -> String? { substitutes[family.lowercased()] }
}
