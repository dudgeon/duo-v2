// Writes shots.json for the 0.2.22 film from this file (the beats are easier to read and change here than in JSON):
//   node films/release-0-2-22/make-shots.mjs      (from video/), then node build.mjs --film release-0-2-22 --check
// A frame is placed from a pane anchor so its 1.12 fit lands on the pane's edges, with room under it for the caption band.
import {readFileSync, writeFileSync} from 'node:fs';
const here = new URL('.', import.meta.url).pathname;
const old = JSON.parse(readFileSync(here + 'shots.json', 'utf8'));
const frame = (pane, px, py, left, top, fw) => { const fh = fw * 9 / 16, w = fw / 1.12, h = fh / 1.12;
  return {rel: pane, dx: +(left + (fw - w) / 2 - px).toFixed(1), dy: +(top + (fh - h) / 2 - py).toFixed(1), w: +w.toFixed(1), h: +h.toFixed(1)}; };
const M = (top, left = 300, fw = 839) => frame('video.pane.middle', 300, 40, left, top, fw);
const after = (o) => ({line: 1, word: 'macos', offset: +(0.6 + o).toFixed(2)});   // from the end of S1's first line
const S = {
  $note: "The 0.2.22 release film (DL-279), written by make-shots.mjs. S0 the title card; S1 to S4 app scenes (`rel-app`) on the video-vv-* and video-vc-* states (Sources/DuoKit/Debug/VideoTargets+Voice.swift); S5 the ending, folding into Classic's Dock icon. The dictation is real: macOS's recognizer hearing fixture/dictation/*.wav through voice input's file path (fixture/make-dictation.py); the film plays those clips where the mic hears them.",
  S0: {kind: 'drawn', scene: 'rel-title', leadIn: 1.0, tail: -0.7, thumbnail: -0.2, states: ['video-vv-chat-rest'],
    words: {version: '0.2.22', lines: ['Voice input, and Classic', 'Talk to Claude by voice, and the v1 paper look']},
    events: {title: {line: 1, offset: 0.2}, sub: {line: 1, word: 'things'}},
    requires: [
      {what: 'The intro\'s title card: the Duo icon builds itself on the High Sierra wallpaper', by: ['src:src/scenes/release/Title.tsx', 'src:src/lib/DuoIcon.tsx']},
      {what: 'Beside "Duo 0.2.22", "Voice input, and Classic" over "A mic in chat and the terminal, and the v1 paper look"', by: ['event:title', 'event:sub']},
      {what: 'The settled frame is the thumbnail (frame 0)', by: ['event:sub', 'src:build.mjs']},
      {what: 'The words wipe back, the icon drops into the Dock, and the window opens out of it on Sam\'s shelf-scan project in Light', by: ['src:src/scenes/release/Title.tsx', 'state:video-vv-chat-rest']}]},
  S1: {kind: 'drawn', scene: 'rel-app', transitionIn: 'rel-open', leadIn: 0.9, states: ['video-vv-chat-rest'], pauses: {1: 6.6}, tail: 0.5,
    beats: [
      {id: 'push', at: {line: 1, offset: -0.6}, in: 'video-vv-chat-rest', cam: M(663), dur: 1.2},
      {id: 'mic-mark', at: {line: 1, word: 'voice'}, in: 'video-vv-chat-rest', mark: 'voice.mic', hold: 1.6},
      // The real app, recorded while it hears the dictation (video-vv-chat-rec): the words land when the recognizer writes them.
      {id: 'mic-click', at: after(0.5), click: 'voice.mic', in: 'video-vv-chat-rest', rec: 'video-vv-chat-rec', recFrom: 0.4, recFor: 6.2, audio: 'chat'},
      {id: 'words-mark', at: {line: 2, word: 'second'}, in: 'video-vv-chat-rec', mark: 'video.composer', hold: 1.6},
      {id: 'return', at: {line: 3, word: 'return'}, key: '↩', in: 'video-vv-chat-sent', state: 'video-vv-chat-sent', stateAfter: 0.08}],
    requires: [
      {what: 'The camera pushes in on the Auto-add decision chat\'s composer and the mic at its right end', by: ['#push', '#mic-mark']},
      {what: 'The cursor clicks the mic: it fills, and the hint row\'s level meter moves with the voice', by: ['#mic-click']},
      {what: 'We hear Sam\'s dictation, and the words land in the composer as the recognizer settles them, a phrase at a time, at the real delay of a run on this Mac (the meter moving with nothing written, then each phrase); nothing is sent', by: ['#mic-click', '#words-mark', 'state:video-vv-chat-rec']},
      {what: 'On "press Return" the Return key shows as a keycap and the message goes into the chat', by: ['#return']}]},
  S2: {kind: 'drawn', scene: 'rel-app', transitionIn: 'rel-carry', leadIn: 0.6, states: ['video-vv-chat-sent'], pauses: {1: 6.4}, tail: 0.5,
    beats: [
      {id: 'tab', at: {line: 1, offset: -0.2}, click: 'video.tab.middle.0', in: 'video-vv-chat-sent', state: 'video-vv-term-live', cam: M(250), dur: 1.0},
      {id: 'termmic-mark', at: {line: 1, word: 'terminal'}, in: 'video-vv-term-live', mark: 'video.vv.termmic', hold: 1.4},
      // ⇧⌘D held while the dictation is heard; the real app recorded (video-vv-term-rec): bars, and each phrase pasted as it settles.
      {id: 'hold', at: {line: 1, word: 'talk', offset: 0.5}, key: '⇧⌘D', keyHold: 4.6, in: 'video-vv-term-live', rec: 'video-vv-term-rec', recFrom: 0.4, recFor: 5.8, audio: 'terminal'}],
    requires: [
      {what: 'The cursor clicks the Tighten PRD goals tab: Claude Code\'s terminal with the small mic beside its input box', by: ['#tab', '#termmic-mark']},
      {what: 'On "Shift-Command-D" the keys show held; the mic turns into three level bars that move as Sam speaks', by: ['#hold', 'state:video-vv-term-rec']},
      {what: 'Each phrase lands in Claude\'s prompt as it settles; the keys let go and the mic comes back; nothing is sent', by: ['#hold', 'state:video-vv-term-rec']}]},
  S4: {kind: 'drawn', scene: 'rel-app', transitionIn: 'rel-carry', leadIn: 0.8, states: ['video-vv-term-rec'], tail: 1.0,
    beats: [
      // Back to the chat, then the middle and right panes from the divider to the window's edge: Settings large enough to read.
      {id: 'back', at: {line: 1, offset: -0.7}, click: 'video.tab.middle.3', in: 'video-vv-term-rec', state: 'video-vv-chat-sent'},
      {id: 'wide', at: {line: 1, offset: -0.2}, in: 'video-vv-chat-sent', cam: M(100, 300, 1500), dur: 1.0},
      {id: 'settings', at: {line: 1, word: 'settings', offset: -0.2}, in: 'video-vv-chat-sent', overlay: {state: 'video-vc-settings-light', x: 560, y: 150, scale: 2, title: 'Duo Settings',
        region: {x: 0, y: 0, w: 680, h: 230}, until: {line: 1, word: 'appearance', offset: 0.7}}},
      {id: 'menu', at: {line: 1, word: 'appearance'}, in: 'video-vv-chat-sent', menu: {on: {x: 705, y: 186, w: 100, h: 18}, items: ['Match System', 'Light', 'Dark', 'Classic'], pick: 'Classic', pickAfter: 0.55, hold: 0.8}, fx: 0.3},
      {id: 'classic', at: {line: 1, word: 'appearance', offset: 0.6}, in: 'video-vc-classic', state: 'video-vc-classic', stateAfter: 0.05, fade: 0.35, dockIcon: 'classic'},
      {id: 'settings-classic', at: {line: 1, word: 'appearance', offset: 0.7}, in: 'video-vc-classic', overlay: {state: 'video-vc-settings-classic', x: 560, y: 150, scale: 2, title: 'Duo Settings',
        region: {x: 0, y: 0, w: 680, h: 230}, until: {line: 2, offset: 0.9}}},
      {id: 'close-settings', at: {line: 2, offset: 0.85}, click: {x: 573, y: 130, w: 12, h: 12}, in: 'video-vc-classic'},
      {id: 'orange', at: {line: 2, word: 'orange'}, in: 'video-vc-classic', cam: M(30), dur: 0.9},
      {id: 'rule-mark', at: {line: 2, word: 'line'}, in: 'video-vc-classic', mark: {on: 'video.pane.middle', y0: 0, y1: 0.004}, hold: 1.2},
      {id: 'buttons-mark', at: {line: 3, word: 'buttons'}, in: 'video-vc-classic', mark: 'New session or shell', hold: 1.8},
      {id: 'pull-back', at: {line: 3, word: 'buttons', offset: 1.0}, in: 'video-vc-classic', cam: 'wide', dur: 1.0}],
    requires: [
      {what: 'Duo\'s Settings window opens over the main window', by: ['#settings']},
      {what: 'The cursor clicks Appearance\'s menu (Match System, Light, Dark, Classic) and picks Classic', by: ['#menu']},
      {what: 'The main window turns to Classic\'s warm paper, and so does Settings, with its Classic line under Appearance', by: ['#classic', '#settings-classic']},
      {what: 'The cursor closes Settings', by: ['#close-settings']},
      {what: 'On "orange line" the camera moves to the top of the middle pane and its orange rule', by: ['#orange', '#rule-mark']},
      {what: 'On "new buttons" the camera is at the end of the middle pane\'s tab strip: the + and the split pill, one click each (DL-253)', by: ['#buttons-mark']}]},
  // Cut for cut 3 (Geoff, Nov 1: "Don't mention the no-mic state, that's not important").
  $cutNoMic: {kind: 'drawn', scene: 'rel-app', transitionIn: 'rel-carry', leadIn: 0.6, states: ['video-vv-term-done'], tail: 1.0,
    beats: [
      {id: 'back', at: {line: 1, offset: -0.3}, click: 'video.tab.middle.3', in: 'video-vv-term-done', state: 'video-vv-nomic', cam: M(663), dur: 1.0},
      {id: 'nomic-mark', at: {line: 1, word: 'struck'}, in: 'video-vv-nomic', mark: 'voice.mic', hold: 1.5}],
    requires: [
      {what: 'Back in the chat, the camera close on the composer', by: ['#back']},
      {what: 'The mic is faint with a line through it, as with no microphone connected', by: ['#nomic-mark', 'state:video-vv-nomic']}]},
  S5: {kind: 'drawn', scene: 'rel-end', transitionIn: 'rel-close', leadIn: 0.4, tail: 2.3, states: ['video-vc-classic'],
    words: {version: '0.2.22', lines: ['Voice input, and Classic', 'Talk to Claude by voice, and the v1 paper look'], icon: 'classic',
      foot: ['github.com/dudgeon/duo-v2/issues', 'Duo › Check for Updates…']},
    events: {fold: {line: 1, word: 'github', offset: -0.9}, card: {line: 1, word: 'issue'}, foot: {line: 1, word: 'github'}},
    requires: [
      {what: 'The camera pulls back to the whole window, which folds back into its Classic Dock icon', by: ['transition', 'event:fold']},
      {what: 'The title card returns with the Classic icon, with "github.com/dudgeon/duo-v2/issues" and "Duo › Check for Updates…" under it', by: ['event:card', 'event:foot', 'src:src/scenes/release/Title.tsx']},
      {what: 'Held about 2 s after the line', by: ['event:foot']}]},
};
// The hash of each scene's Shot: note this file was written against (check.mjs stops when a note changes).
const SHA = {S0: '62f7c94cb596', S1: 'd5ccf43b95b4', S2: '8e0f0d029d14', S4: 'e140ed33aac2', S5: '3c8253584c68'};
for (const k of Object.keys(SHA)) S[k].shotSha = SHA[k];
writeFileSync(here + 'shots.json', JSON.stringify(S, null, 2) + '\n');
console.log('shots.json written');
