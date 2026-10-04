/// The script Duo injects into local HTML pages (DL-67, DL-70): reports the selection, and runs
/// the element picker (LR-44: off → hover outline → click to freeze → explicit send; Esc exits).
/// The outline uses the system `Highlight` colour; it's restyled once designed (Q-21).
enum HTMLPicker {
    static let script = #"""
(() => {
  if (window.__duo) return;
  const post = (m) => { try { webkit.messageHandlers.duoPage.postMessage(m); } catch (_) {} };
  let lastContext = null;
  document.addEventListener("contextmenu", (e) => { lastContext = e.target; }, true);

  const fileOrURL = (u) => {
    try { const x = new URL(u, document.baseURI); return x.protocol === "file:" ? decodeURIComponent(x.pathname) : x.href; }
    catch (_) { return u; }
  };
  const image = (img) => ({ src: fileOrURL(img.getAttribute("src") || img.currentSrc || ""), alt: img.getAttribute("alt") || "" });

  function selection() {
    const sel = window.getSelection();
    const images = [];
    let text = "";
    if (sel && sel.rangeCount && !sel.isCollapsed) {
      text = sel.toString();
      for (let i = 0; i < sel.rangeCount; i++) {
        const frag = sel.getRangeAt(i).cloneContents();
        frag.querySelectorAll("img").forEach((img) => images.push(image(img)));
        // A selection made of one image clones it as the fragment's only child.
        if (frag.firstChild && frag.firstChild.nodeName === "IMG" && !images.length) images.push(image(frag.firstChild));
      }
    }
    if (!text && !images.length && lastContext && lastContext.nodeName === "IMG") images.push(image(lastContext));
    if (!text.trim() && !images.length) return null;
    return { text, images, title: document.title };
  }

  // Legacy's selector: tag:nth-child steps up to the first element with a usable id.
  function selector(el) {
    const parts = [];
    for (let e = el; e && e.nodeType === 1 && e !== document.documentElement; e = e.parentElement) {
      if (e.id && /^[A-Za-z][\w-]*$/.test(e.id) && document.querySelectorAll("#" + e.id).length === 1) { parts.unshift("#" + e.id); break; }
      let step = e.localName;
      const sibs = e.parentElement ? Array.from(e.parentElement.children).filter((s) => s.localName === e.localName) : [];
      if (sibs.length > 1) step += ":nth-child(" + (Array.from(e.parentElement.children).indexOf(e) + 1) + ")";
      parts.unshift(step);
    }
    return parts.join(" > ");
  }

  function label(el) {
    let s = el.localName;
    if (el.id) s += "#" + el.id;
    const cls = typeof el.className === "string" ? el.className.trim().split(/\s+/).filter(Boolean).slice(0, 3) : [];
    if (cls.length) s += "." + cls.join(".");
    return s;
  }

  // Headings above the element, outermost first: the nearest preceding h1..h6 at each level.
  function trail(el) {
    const heads = Array.from(document.querySelectorAll("h1,h2,h3,h4,h5,h6"))
      .filter((h) => h !== el && (h.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING || h.contains(el)));
    const out = [];
    let level = 7;
    for (let i = heads.length - 1; i >= 0; i--) {
      const l = Number(heads[i].localName[1]);
      if (l < level) { out.unshift(heads[i].innerText.trim().slice(0, 80)); level = l; }
    }
    return out;
  }

  const KEEP = /^(id|class|href|src|alt|title|role|name|type|placeholder|value|for|action|method|aria-.*|data-.*)$/;
  const STYLES = ["display", "position", "color", "background-color", "font-family", "font-size", "font-weight", "line-height",
                  "padding", "margin", "border", "border-radius", "width", "height", "gap", "box-shadow"];

  function describe(el) {
    const cs = getComputedStyle(el);
    const styles = {};
    for (const p of STYLES) {
      const v = cs.getPropertyValue(p);
      if (v && !["none", "normal", "auto", "0px", "rgba(0, 0, 0, 0)", "static"].includes(v)) styles[p] = v.length > 120 ? v.slice(0, 120) + "…" : v;
    }
    const attributes = {};
    for (const a of Array.from(el.attributes)) if (KEEP.test(a.name) && a.name !== "class" && a.name !== "id") attributes[a.name] = a.value.slice(0, 200);
    const r = el.getBoundingClientRect();
    return {
      tag: el.localName, label: label(el), selector: selector(el), trail: trail(el),
      text: (el.innerText || el.textContent || "").trim().slice(0, 2000),
      attributes, styles, rect: [r.left + scrollX, r.top + scrollY, r.width, r.height],
      html: el.outerHTML.slice(0, 4000), url: location.href, title: document.title,
      viewRect: [r.left, r.top, r.width, r.height],
    };
  }

  // The picker.
  let picking = false, frozen = null, hovered = null;
  const box = document.createElement("div");
  box.setAttribute("data-duo-picker", "");
  box.style.cssText = "position:fixed;pointer-events:none;z-index:2147483647;outline:2px solid Highlight;" +
    "background:color-mix(in srgb, Highlight 18%, transparent);border-radius:2px;display:none;transition:all 60ms";
  const place = (el) => {
    if (!el) { box.style.display = "none"; return; }
    const r = el.getBoundingClientRect();
    Object.assign(box.style, { display: "block", left: r.left + "px", top: r.top + "px", width: r.width + "px", height: r.height + "px" });
  };
  const over = (e) => { if (!picking || frozen) return; hovered = e.target; place(hovered); };
  const click = (e) => {
    if (!picking) return;
    e.preventDefault(); e.stopPropagation();
    frozen = e.target; place(frozen);
    post({ kind: "picked", element: describe(frozen) });
  };
  const key = (e) => { if (picking && e.key === "Escape") { e.preventDefault(); stop(); post({ kind: "pickEnded" }); } };
  const swallow = (e) => { if (picking) { e.preventDefault(); e.stopPropagation(); } };
  const rescroll = () => place(frozen || hovered);

  function start() {
    if (!box.isConnected) document.documentElement.appendChild(box);
    picking = true; frozen = null;
    hovered = lastContext; place(hovered);
    document.documentElement.style.cursor = "crosshair";
  }
  function stop() { picking = false; frozen = null; hovered = null; place(null); document.documentElement.style.cursor = ""; }
  function unfreeze() { frozen = null; }

  document.addEventListener("mouseover", over, true);
  document.addEventListener("click", click, true);
  document.addEventListener("mousedown", swallow, true);
  document.addEventListener("mouseup", swallow, true);
  document.addEventListener("keydown", key, true);
  addEventListener("scroll", rescroll, true);
  addEventListener("resize", rescroll);

  window.__duo = {
    selection, start, stop, unfreeze,
    hideOutline: () => { box.style.display = "none"; },
    showOutline: () => place(frozen || hovered),
    // For the CLI: describe the element a selector names, without the picker.
    describe: (sel) => { const el = document.querySelector(sel); return el ? describe(el) : null; },
    picking: () => picking,
    freeze: (sel) => { const el = document.querySelector(sel); if (el) { frozen = el; place(el); } },
  };
})();
"""#
}
