// `@` autocomplete in the margin's comment fields (comment-at, DL-133's menu sized for the margin card).
// Typing `@` after a space or at the start opens a menu under the field; Claude is always its first item (DL-236 9).
// The pure parts (trigger, filter, keys, insertion) have no DOM, so test/atmenu.test.mjs runs them under node.

export const AT_ITEMS = [{ name: "claude", hint: "to a session" }];

/** The `@word` the caret is in the middle of, if it began at the start or after whitespace: { start, query }. */
export function atQuery(value, caret) {
  let i = caret;
  while (i > 0 && /[\w-]/.test(value[i - 1])) i--;
  if (i === 0 || value[i - 1] !== "@") return null;
  const start = i - 1;
  if (start > 0 && !/\s/.test(value[start - 1])) return null;
  return { start, query: value.slice(i, caret) };
}

/** Items whose name starts with what's been typed, Claude first. */
export function atFilter(query, items = AT_ITEMS) {
  const q = query.toLowerCase();
  return items.filter((it) => it.name.toLowerCase().startsWith(q));
}

/** What a key does while the menu is open: "up" | "down" | "insert" | "close", or null to leave it to the field. */
export function atKey(e) {
  if (e.metaKey || e.ctrlKey || e.altKey) return null;
  if (e.key === "ArrowUp") return "up";
  if (e.key === "ArrowDown") return "down";
  if ((e.key === "Enter" && !e.shiftKey) || e.key === "Tab") return "insert";
  if (e.key === "Escape") return "close";
  return null;
}

/** The field's text with `@query` (from start to caret) replaced by `@name `, and where the caret goes. */
export function atInsert(value, start, caret, name) {
  const tail = value.slice(caret);
  const add = "@" + name + (/^\s/.test(tail) ? "" : " ");
  return { text: value.slice(0, start) + add + tail, caret: start + add.length };
}

const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

/** Wires the menu to a textarea inside `card` (positioned). `onInput` runs after an insertion so the card re-places. */
export function attachAtMenu(field, card, onInput) {
  let menu = null, st = null;   // st: { start, items, sel }
  const close = () => { if (menu) menu.remove(); menu = null; st = null; };
  const draw = () => {
    // A popover, not part of the card (composer-at): a child of the margin layer, floating over the card's lower part
    // and whatever is under it, so the card keeps its border and size.
    const layer = card.parentElement;
    if (!layer) return;
    if (!menu) { menu = el("div", "duo-mg-at"); menu.dataset.atMenu = "1"; menu.style.visibility = "hidden"; layer.append(menu); }
    menu.replaceChildren();
    st.items.forEach((it, i) => {
      const row = el("div", "duo-mg-at-row" + (i === st.sel ? " duo-mg-at-sel" : ""));
      row.dataset.atItem = it.name;
      row.append(el("span", "duo-mg-at-name" + (it.name === "claude" ? " duo-mg-claude" : ""), it.name), el("span", "duo-mg-at-hint", it.hint));
      row.addEventListener("mousedown", (e) => { e.preventDefault(); insert(it); });
      menu.append(row);
    });
    // Under the field, at the card's width; above it when the window has no room below. Again next frame: the margin
    // places the card (its width, its left) after the input that opened the menu.
    const m = menu;
    const position = () => {
      if (!m.isConnected) return;
      const lr = layer.getBoundingClientRect(), cr = card.getBoundingClientRect(), fr = field.getBoundingClientRect();
      m.style.left = (cr.left - lr.left) + "px";
      m.style.width = cr.width + "px";
      const h = m.offsetHeight;
      m.style.top = ((fr.bottom + 4 + h > window.innerHeight && fr.top - 4 - h > 0) ? fr.top - lr.top - 4 - h : fr.bottom - lr.top + 4) + "px";
      m.style.visibility = "";
    };
    position();
    requestAnimationFrame(position);
  };
  const refresh = () => {
    const q = atQuery(field.value, field.selectionStart);
    const items = q ? atFilter(q.query) : [];
    if (!q || !items.length) { close(); return; }
    st = { start: q.start, items, sel: Math.min(st ? st.sel : 0, items.length - 1) };
    draw();
  };
  const insert = (it) => {
    const r = atInsert(field.value, st.start, field.selectionStart, it.name);
    field.value = r.text; field.setSelectionRange(r.caret, r.caret); field.focus();
    close(); if (onInput) onInput();
  };
  field.addEventListener("keydown", (e) => {
    if (!st) return;
    const a = atKey(e);
    if (!a) return;
    e.preventDefault(); e.stopImmediatePropagation();
    if (a === "close") close();
    else if (a === "insert") insert(st.items[st.sel]);
    else { st.sel = (st.sel + (a === "down" ? 1 : st.items.length - 1)) % st.items.length; draw(); }
  });
  field.addEventListener("input", refresh);
  field.addEventListener("click", refresh);
  field.addEventListener("blur", () => setTimeout(close, 0));
  return { close, refresh };
}

// The popover's shadow and ring are composer-at's; the page's --duo-shadow is only the colour.
export const atTheme = {
  ".duo-mg-at": { position: "absolute", zIndex: "5", boxSizing: "border-box", backgroundColor: "var(--duo-pane)", borderRadius: "10px", boxShadow: "0 8px 24px var(--duo-shadow), 0 0 0 1px color-mix(in srgb, var(--duo-text) 8%, transparent)", padding: "5px" },
  ".duo-mg-at-row": { display: "flex", alignItems: "center", gap: "8px", padding: "4px 10px", borderRadius: "6px", font: "13px/20px -apple-system, BlinkMacSystemFont, sans-serif", cursor: "default" },
  ".duo-mg-at-sel": { backgroundColor: "var(--duo-selected)" },
  ".duo-mg-at-name": { fontFamily: "'SF Mono', ui-monospace, monospace", fontSize: "12px" },
  ".duo-mg-at-hint": { color: "var(--duo-text2)", marginLeft: "auto", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", minWidth: "0" },
};
