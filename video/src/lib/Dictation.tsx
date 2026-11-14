import {Audio, Sequence, useVideoConfig} from 'remotion';
import chatClip from '../../fixture/dictation/chat.wav';
import terminalClip from '../../fixture/dictation/terminal.wav';
import documentClip from '../../fixture/dictation/document.wav';

/** The dictation clips (fixture/make-dictation.mjs), heard as the mic hears them: the 0.2.22 film's chat and terminal, and the
 *  intro's document (S13). Each is Geoff's voice saying what the app's real recognizer then writes. */
export const CLIPS: Record<string, string> = {chat: chatClip, terminal: terminalClip, document: documentClip};

/** A scene's dictation clips, each from its beat's time (`audio` in shots.json; `from` skips that far in, with the recording). */
export const DictationAudio = ({audio}: {audio?: {at: number; clip: string; from?: number}[]}) => {
  const {fps} = useVideoConfig();
  return <>{(audio ?? []).map((a, i) => (
    <Sequence key={i} from={Math.round(a.at * fps)}><Audio src={CLIPS[a.clip]} startFrom={Math.round((a.from ?? 0) * fps)} /></Sequence>
  ))}</>;
};
