// Writes the intro's v12 shots (S12 Comments and suggestions, S13 Voice input, S14 Windows) into shots.json, and points S8 and
// S9 at S13's last picture. Beats are easier to read and change here than in JSON:
//   node films/intro-v12-shots.mjs      (from video/), then node build.mjs --check
// S12 follows the 0.2.21 film's review beats on the same states (video-rv-*), with review in the formatting bar (DL-317).
// S13 is the real dictation (fixture/dictation/*.wav heard through voice input's file path, at its measured delay; the 0.2.22
// film's recordings for chat and the terminal, and video-rv-doc-rec for the document). S14 opens two more windows, each its
// own capture (video-mw-*), cascaded over the first on the desk.
import {readFileSync, writeFileSync} from 'node:fs';
const f = new URL('../shots.json', import.meta.url).pathname;
const s = JSON.parse(readFileSync(f, 'utf8'));
const R = (dy) => ({rel: 'video.pane.right', dx: 38.6, dy, w: 642.9, h: 361.6});   // the right pane at 16:9, from the 0.2.21 film
// The bar's right end: its controls share the document's identifier, so they're placed from the mode button's first part (its
// pen, label "Mode: …"): the whole button, and the mic 3 pt after it (as they are while Suggesting).
const MODE = {rel: 'Mode:', dx: 0, dy: -4.5, w: 87.5, h: 16}, DOCMIC = {rel: 'Mode:', dx: 97.5, dy: -6.5, w: 20, h: 20};
const midChat = {rel: 'video.pane.middle', dx: 44.9, dy: 585.3, w: 749.1, h: 421.4};

s.S12 = {kind: 'drawn', scene: 'app', transitionIn: 'carry-on', leadIn: 0.6, states: ['video-s7-html-after'], pauses: {1: 6.2, 2: 3.2, 4: 1.0}, tail: 0.8,
  beats: [
    {id: 'prd-tab', at: {line: 1, offset: -0.5}, click: 'video.tab.md', in: 'video-s7-html-after', state: 'video-rv-open', cam: R(389.7), dur: 1.2},
    {id: 'margin-mark', at: {line: 1, word: 'margin'}, in: 'video-rv-open', mark: {fit: ['video.rv.card.c1', 'video.rv.card.c2'], pad: 2}, hold: 1.9},
    {id: 'select-onetap', at: {line: 1, word: 'docs', offset: 0.3}, in: 'video-rv-sel-onetap', drag: {from: 'video.rv.text.oneTap', fx0: 0, fx1: 1, dur: 0.8, reveal: 'video-rv-sel-onetap'}, state: 'video-rv-sel-onetap', stateAfter: 0.8},
    {id: 'comment-button', at: {line: 1, word: 'docs', offset: 1.5}, click: 'Add Comment ⌥⌘M', key: '⌥⌘M', in: 'video-rv-sel-onetap', state: 'video-rv-compose-onetap-empty', stateAfter: 0.06},
    {id: 'type-comment-start', at: {line: 1, word: 'docs', offset: 2.1}, in: 'video-rv-compose-onetap-blank', state: 'video-rv-compose-onetap-blank', stateAfter: 0},
    {id: 'type-comment', at: {line: 1, word: 'docs', offset: 2.1}, in: 'video-rv-compose-onetap-row1', wipe: {state: 'video-rv-compose-onetap-row1', on: {on: 'video.rv.composer.field', y0: 0, y1: 0.5}, dur: 0.9, chars: 22}, state: 'video-rv-compose-onetap-row1', stateAfter: 0.9},
    {id: 'type-comment-row2', at: {line: 1, word: 'docs', offset: 3.0}, in: 'video-rv-compose-onetap', wipe: {state: 'video-rv-compose-onetap', on: {on: 'video.rv.composer.field', y0: 0.5, y1: 1}, dur: 0.8, chars: 27}, state: 'video-rv-compose-onetap', stateAfter: 0.8},
    {id: 'post', at: {line: 1, word: 'docs', offset: 4.1}, click: 'video.rv.composer.post', in: 'video-rv-compose-onetap', state: 'video-rv-commented'},
    // On the way to line 2: Lena's answered thread, closed and kept, so the margin has room.
    {id: 'open-lena', at: {line: 1, word: 'docs', offset: 4.9}, click: 'video.rv.card.c1', fy: 0.3, in: 'video-rv-commented', state: 'video-rv-c1-active'},
    {id: 'close-keep', at: {line: 1, word: 'docs', offset: 5.7}, click: 'video.rv.card.close', in: 'video-rv-c1-active', state: 'video-rv-closed'},
    {id: 'glare-frame', at: {line: 2, offset: -0.4}, in: 'video-rv-closed', cam: R(601.7), dur: 0.9},
    {id: 'select-glare', at: {line: 2, word: 'mention', offset: -0.3}, in: 'video-rv-sel-glare', drag: {from: 'video.rv.text.glare', fx0: 0, fx1: 1, dur: 0.7, reveal: 'video-rv-sel-glare'}, state: 'video-rv-sel-glare', stateAfter: 0.7},
    {id: 'add-glare-comment', at: {line: 2, word: 'mention', offset: 0.7}, key: '⌥⌘M', in: 'video-rv-compose-glare-empty', state: 'video-rv-compose-glare-empty', stateAfter: 0.06},
    {id: 'type-claude-start', at: {line: 2, word: 'mention', offset: 1.2}, in: 'video-rv-compose-glare-blank', state: 'video-rv-compose-glare-blank', stateAfter: 0},
    {id: 'type-claude', at: {line: 2, word: 'mention', offset: 1.2}, in: 'video-rv-compose-glare-row1', wipe: {state: 'video-rv-compose-glare-row1', on: {on: 'video.rv.composer.field', y0: 0, y1: 0.5}, dur: 1.3, chars: 20}, state: 'video-rv-compose-glare-row1', stateAfter: 1.3},
    {id: 'type-claude-row2', at: {line: 2, word: 'mention', offset: 2.5}, in: 'video-rv-compose-glare', wipe: {state: 'video-rv-compose-glare', on: {on: 'video.rv.composer.field', y0: 0.5, y1: 1}, dur: 1.3, chars: 40}, state: 'video-rv-compose-glare', stateAfter: 1.3},
    {id: 'pill-mark', at: {line: 2, word: 'pill'}, in: 'video-rv-compose-glare', mark: 'video.rv.composer.pill', hold: 1.5},
    {id: 'post-claude', at: {line: 2, word: 'pill', offset: 1.6}, click: 'video.rv.composer.post', in: 'video-rv-compose-glare', state: 'video-rv-sent'},
    {id: 'sent-mark', at: {line: 2, word: 'pill', offset: 2.1}, in: 'video-rv-sent', mark: 'video.rv.card.status', hold: 0.9},
    {id: 'to-chat', at: {line: 2, word: 'pill', offset: 2.7}, in: 'video-rv-sent', cam: midChat, dur: 1},
    {id: 'working', at: {line: 2, word: 'pill', offset: 3.7}, in: 'video-rv-working', state: 'video-rv-working'},
    {id: 'back-to-doc', at: {line: 3, offset: -0.2}, in: 'video-rv-replied', cam: R(621.7), dur: 1},
    {id: 'replied', at: {line: 3, word: 'change'}, in: 'video-rv-replied', state: 'video-rv-replied', stateAfter: 0, fade: 0.5},
    {id: 'change-mark', at: {line: 3, word: 'change', offset: 0.5}, in: 'video-rv-replied', mark: 'video.rv.text.glareNew', hold: 1.1},
    {id: 'reply-mark', at: {line: 3, word: 'thread'}, in: 'video-rv-replied', mark: 'video.rv.card.reply', hold: 1.6},
    // Line 4: the mode menu at the bar's right end (Duo's own, captured), Suggesting picked; Sam's edit beside Jo's and Ravi's.
    {id: 'bar-frame', at: {line: 4, offset: -0.5}, in: 'video-rv-replied', cam: R(21.7), dur: 1},
    {id: 'mode-open', at: {line: 4, word: 'editing'}, click: 'Mode:', in: 'video-rv-replied', state: 'video-rv-mode-menu', stateAfter: 0.05},
    {id: 'mode-pick', at: {line: 4, word: 'suggesting'}, click: 'Suggesting', in: 'video-rv-mode-menu', state: 'video-rv-suggest-on', stateAfter: 0.08},
    {id: 'mode-mark', at: {line: 4, word: 'suggesting', offset: 0.4}, in: 'video-rv-suggest-on', mark: MODE, hold: 1.2},
    {id: 'goals-frame', at: {line: 4, word: 'edits'}, in: 'video-rv-suggest-on', cam: R(411.7), dur: 0.8},
    {id: 'type-goal', at: {line: 4, word: 'suggestions', offset: -0.3}, in: 'video-rv-typed', wipe: {state: 'video-rv-typed', on: 'video.rv.mark.s3', dur: 0.9}, state: 'video-rv-typed', stateAfter: 0.9},
    {id: 'colours', at: {line: 4, word: 'color', offset: -0.6}, in: 'video-rv-typed', cam: {fit: ['video.rv.mark.s1', 'video.rv.mark.s2', 'video.rv.mark.s3'], pad: 60}, dur: 0.9,
      mark: {fit: ['video.rv.mark.s1', 'video.rv.mark.s2', 'video.rv.mark.s3'], pad: 6}, hold: 1.8},
    {id: 'open-s1', at: {line: 5, word: 'accept', offset: -0.9}, click: 'video.rv.mark.s1', in: 'video-rv-typed', state: 'video-rv-hover-s1'},
    {id: 'accept', at: {line: 5, word: 'accept', offset: 0.2}, click: 'video.rv.tip.accept', in: 'video-rv-hover-s1', state: 'video-rv-accepted'},
    {id: 'open-s2', at: {line: 5, word: 'reject', offset: -0.7}, click: 'video.rv.mark.s2', fx: 0.3, in: 'video-rv-accepted', state: 'video-rv-hover-s2'},
    {id: 'reject', at: {line: 5, word: 'reject', offset: 0.4}, click: 'video.rv.tip.reject', in: 'video-rv-hover-s2', state: 'video-rv-rejected'}],
  requires: [
    {what: 'Carrying on from S7, the cursor clicks the PRD tab', by: ['transition', '#prd-tab']},
    {what: 'On "comments" the outline traces the margin\'s cards (Ravi\'s and Lena\'s)', by: ['#margin-mark']},
    {what: 'Sam selects "Fixing a flagged book takes one tap", clicks Comment (⌥⌘M keycaps), types "Lena, can you mock the one-tap fix for Thursday?", Post', by: ['#select-onetap', '#comment-button', '#type-comment', '#type-comment-row2', '#post']},
    {what: 'Lena\'s answered thread closed with Close and Keep on the way to line 2', by: ['#open-lena', '#close-keep']},
    {what: 'The glare requirement selected; "@claude can you make this one testable? …" typed; To and the session pill appear; the outline traces the pill on "pill"; Post; Sent', by: ['#select-glare', '#add-glare-comment', '#type-claude', '#type-claude-row2', '#pill-mark', '#post-claude', '#sent-mark']},
    {what: 'Line 3: the comment arrives in the Auto-add decision chat, Claude works (card: Claude is replying), then the requirement changes in place and Claude\'s reply sits in the thread in Claude\'s green', by: ['#to-chat', '#working', '#back-to-doc', '#replied', '#change-mark', '#reply-mark']},
    {what: 'Line 4: the mode menu at the bar\'s right end (Editing ⌄, Duo\'s own, captured) with its real items; Suggesting picked; the label reads Suggesting ⌄', by: ['#bar-frame', '#mode-open', '#mode-pick', '#mode-mark', 'state:video-rv-mode-menu']},
    {what: 'Sam changes 80% to 85%, shown as his suggestion; on "own color" the camera shows it beside Jo\'s and Ravi\'s, each in their colour', by: ['#goals-frame', '#type-goal', '#colours']},
    {what: 'Line 5: Jo\'s suggestion accepted, Ravi\'s rejected, from their labels', by: ['#open-s1', '#accept', '#open-s2', '#reject']}]};

// S13: the document (the bar's mic, recorded), chat (the 0.2.22 recording), the terminal (⇧⌘D held, the 0.2.22 recording).
const M = (top, left = 300, fw = 839) => { const fh = fw * 9 / 16, w = fw / 1.12, h = fh / 1.12; return {rel: 'video.pane.middle', dx: +(left + (fw - w) / 2 - 300).toFixed(1), dy: +(top + (fh - h) / 2 - 40).toFixed(1), w: +w.toFixed(1), h: +h.toFixed(1)}; };
s.S13 = {kind: 'drawn', scene: 'app', transitionIn: 'carry-on', leadIn: 0.6, states: ['video-rv-rejected'], pauses: {2: 1.2, 3: 2.6, 4: 3.4, 5: 6.0}, tail: 0.6,
  beats: [
    {id: 'caret', at: {line: 1, offset: 0.2}, click: 'video.rv.text.heardEnd', fx: 1, in: 'video-rv-rejected', state: 'video-rv-doc-rest', stateAfter: 0.05, cam: R(21.7), dur: 1.0},
    {id: 'doc-mic-mark', at: {line: 2, word: 'mic'}, in: 'video-rv-doc-rest', mark: DOCMIC, hold: 1.3},
    {id: 'doc-mic', at: {line: 2, word: 'talking', offset: 0.1}, click: DOCMIC, in: 'video-rv-doc-rest', rec: 'video-rv-doc-rec', recFrom: 0.6, recFor: 5.8, audio: 'document'},
    {id: 'doc-words', at: {line: 3, word: 'show'}, in: 'video-rv-doc-rec', cam: {fit: ['Mode:', 'video.rv.text.heardEnd'], pad: 40}, dur: 1.2},
    {id: 'chat-frame', at: {line: 4, offset: -0.5}, click: 'video.tab.middle.3', in: 'video-rv-doc-rec', state: 'video-vv-chat-rest', cam: M(663), dur: 1.1},
    {id: 'chat-mic', at: {line: 4, word: 'mic'}, click: 'voice.mic', in: 'video-vv-chat-rest', rec: 'video-vv-chat-rec', recFrom: 0.4, recFor: 6.2, audio: 'chat'},
    {id: 'return', at: {line: 4, word: 'return', offset: 6.0}, key: '↩', in: 'video-vv-chat-sent', state: 'video-vv-chat-sent', stateAfter: 0.08},
    {id: 'term-tab', at: {line: 5, offset: -0.3}, click: 'video.tab.middle.0', in: 'video-vv-chat-sent', state: 'video-vv-term-live', cam: M(250), dur: 1.0},
    {id: 'termmic-mark', at: {line: 5, word: 'terminal'}, in: 'video-vv-term-live', mark: 'video.vv.termmic', hold: 1.2},
    {id: 'hold', at: {line: 5, word: 'talk', offset: 0.3}, key: '⇧⌘D', keyHold: 4.6, in: 'video-vv-term-live', rec: 'video-vv-term-rec', recFrom: 0.4, recFor: 5.8, audio: 'terminal'}],
  requires: [
    {what: 'The caret at the end of What we heard; the camera on the bar\'s right end', by: ['#caret']},
    {what: 'On "mic" the outline traces the document mic; the cursor clicks it; the meter, Listening and its keys replace the controls', by: ['#doc-mic-mark', '#doc-mic', 'state:video-rv-doc-rec']},
    {what: 'A real dictation in your voice ("Owen said the second scan was fine once he moved out of the glare."), the meter moving with nothing written, then the phrase landing at the caret at the real delay', by: ['#doc-mic', '#doc-words', 'state:video-rv-doc-rec']},
    {what: 'Line 4: the chat composer\'s mic clicked, its level bars, the words landing a phrase at a time at the real delay; Return as a keycap sends it', by: ['#chat-frame', '#chat-mic', '#return']},
    {what: 'Line 5: the Tighten PRD goals terminal, its mic; ⇧⌘D held as keycaps; three level bars; the words land in Claude\'s prompt; nothing sent; the scene ends on this terminal', by: ['#term-tab', '#termmic-mark', '#hold']}]};

// S14: window 1 to the Board, Open in New Window (Blue), ⌥⌘N (Ochre), then the Window menu and the bring-forward.
const TILE = ['Open in New Window', '-', 'Send to Claude', 'Send To ▸', '-', 'Move into Home…', 'Merge Into ▸'];
const WINDOW = ['Minimize', 'Zoom', '-', 'Show Previous Tab', 'Show Next Tab', '-', 'Window Colour ▸', '-', 'Bring All to Front', '-', 'Duo', 'beta-feedback', 'neighborhood-map'];
const W2 = {x: 150, y: 120}, W3 = {x: 300, y: 190};
s.S14 = {kind: 'drawn', scene: 'app', transitionIn: 'carry-on', leadIn: 0.6, states: ['video-s9-files-open'], pauses: {1: 0.6, 2: 2.8, 3: 1.4, 4: 4.2}, tail: 0.8,
  beats: [
    {id: 'to-board', at: {line: 1, word: 'window', offset: -0.4}, click: 'video.crumb.all', in: 'video-s9-files-open', state: 'video-s9-board', cam: 'wide', dur: 0.9},
    {id: 'tile-menu', at: {line: 2, word: 'right'}, menu: {on: 'video.board.col.beta-feedback', items: TILE, pick: 'Open in New Window', pickAfter: 0.7, hold: 1.0}, fy: 0.04, in: 'video-s9-board'},
    {id: 'w2-open', at: {line: 2, word: 'window', offset: 0.1}, window: {id: 'w2', state: 'video-mw-beta', ...W2}},
    {id: 'new-window', at: {line: 2, word: 'n', offset: 0.1}, key: '⌥⌘N', window: {id: 'w3', state: 'video-mw-new', ...W3}},
    {id: 'map-tile', at: {line: 2, word: 'one', offset: 0.6}, win: 'w3', click: 'video.board.col.neighborhood-map', fy: 0.05, state: 'video-mw-map', stateAfter: 0.1},
    {id: 'w1-toolbar', at: {line: 3, word: 'color', offset: -0.4}, mark: {on: 'video.pane.left', y0: 0, y1: 0.001}, hold: 0.9},
    {id: 'colours-mark', at: {line: 3, word: 'color', offset: 0.1}, win: 'w2', in: 'video-mw-beta', mark: {rel: 'video.pane.left', x: 0, y: 0, w: 1440, h: 40}, hold: 1.0},
    {id: 'colours-mark-3', at: {line: 3, word: 'apart', offset: -0.4}, win: 'w3', in: 'video-mw-map', mark: {rel: 'video.pane.left', x: 0, y: 0, w: 1440, h: 40}, hold: 1.2},
    {id: 'window-menu', at: {line: 4, word: 'window'}, menu: {on: {x: 92, y: -36, w: 60, h: 18}, items: WINDOW, pick: 'Duo', pickAfter: 1.3, hold: 1.6}, fy: 1.2},
    {id: 'w1-front', at: {line: 4, word: 'window', offset: 1.4}, front: 'main'},
    {id: 'beta-again', at: {line: 4, word: 'already', offset: 0.2}, click: 'video.board.col.beta-feedback', fy: 0.05, in: 'video-s9-board'},
    {id: 'w2-front', at: {line: 4, word: 'already', offset: 0.35}, front: 'w2'},
    {id: 'w1-back', at: {line: 4, word: 'forward', offset: 1.0}, click: {x: 1700, y: 1060, w: 20, h: 20}, in: 'video-s9-board'},
    {id: 'w1-front-2', at: {line: 4, word: 'forward', offset: 1.05}, front: 'main'},
    {id: 'shelf', at: {line: 4, word: 'forward', offset: 2.0}, click: 'video.board.card.Auto-add decision', in: 'video-s9-board', state: 'video-s9-files-open', cam: 'wide', dur: 0.9}],
  requires: [
    {what: 'Carrying on from S9: All projects in the breadcrumb, the Board', by: ['transition', '#to-board']},
    {what: 'The beta-feedback tile\'s menu (drawn, real items) and Open in New Window', by: ['#tile-menu']},
    {what: 'The camera wide on the desk; window 2 opens down and right of the first, on beta-feedback, Blue toolbar and pale blue panes; the first stays plain', by: ['#w2-open']},
    {what: '⌥⌘N keycaps; a third window at All projects in Ochre; its neighborhood-map tile clicked, the window becomes neighborhood-map\'s', by: ['#new-window', '#map-tile']},
    {what: 'On "its own color" the outline traces each window\'s toolbar in turn', by: ['#w1-toolbar', '#colours-mark', '#colours-mark-3']},
    {what: 'The Window menu (drawn, real items, the three windows by title); the first picked and it comes forward', by: ['#window-menu', '#w1-front']},
    {what: 'In the first window the beta-feedback tile clicked: the Blue window comes forward instead of opening it twice', by: ['#beta-again', '#w2-front']},
    {what: 'Back to the first window and its shelf-scan project view, as S9 left it, for S10', by: ['#w1-back', '#w1-front-2', '#shelf']}]};

s.S12.shotSha = 'be30ddd3a786'; s.S13.shotSha = '34f47d945834'; s.S14.shotSha = '4ae93ff61449';
// S8 fades from S13's last picture, and S9 comes back to it.
s.S8.states = s.S8.states.map(() => 'video-vv-term-rec');
s.S9.states[0] = 'video-vv-term-rec';
for (const b of s.S9.beats) if (b.in === 'video-s7-pptx-after') b.in = 'video-vv-term-rec';
s.S9.requires[0].what = 'The pile fades out and Duo fades back in on S13\'s last picture';
// Key order: script order is what plays; keep the file readable in that order too.
const order = ['$note', 'S0', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S12', 'S13', 'S8', 'S9', 'S14', 'S10', 'S11'];
const out = {}; for (const k of order) out[k] = s[k]; for (const k of Object.keys(s)) if (!(k in out)) out[k] = s[k];
writeFileSync(f, JSON.stringify(out, null, 2) + '\n');
console.log('wrote S12, S13, S14');
