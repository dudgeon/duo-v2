const a = await window._docs_annotate_getAnnotatedText('duo-probe');
const t = a.getText(); const s = a.getSelection();
const f = document.querySelector('.docs-texteventtarget-iframe');
return {sel: JSON.stringify(s), text: s && s[0] ? t.slice(s[0].start, s[0].end) : null, active: document.activeElement && (document.activeElement.className||document.activeElement.tagName), tetFocused: f && f.contentDocument.hasFocus()};
