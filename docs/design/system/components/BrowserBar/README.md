A browser tab's bar, and the page shown for a site that isn't on the allow list.

**Status:** Stand-in (DL-3, DL-99, DL-124; DB-20, Q-66, Q-67). **In code:** `Browser/BrowserTabs.swift` `BrowserTabView`, `AddressField`, `DownloadNotice`.

**Anatomy:** 34 high above the page: back, forward and reload (SF Symbols, 12 pt, `text`, disabled `text2`), the address field (a rounded system field, 12 pt, ⌘L focuses it), Open in Browser (`safari`). A not-allowed site: "<host> isn't on your allowed sites", one paragraph in `text2`, and Buttons `Allow <host>` and `Open in Browser`.

**Rules:** only sites on the allow list (and localhost) load in Duo; they stay signed in, and their pages can be sent to Claude. The tab title is the page's title. Open for design (DB-20).

**Browser basics (DL-124), stand-ins:** at any zoom but 100% the bar shows the level (`125%`, body in `text2`) between the address field and Open in Browser; a click is Actual Size (Q-66). A finished download shows S3-4's notice bar (DocumentStateBar's `NoticeBar`) under the bar: "Downloaded <name> to Downloads." with Open (default), Show in Finder and OK (Q-66). A popup's tab sits right after its opener, with no other mark (Q-67).
