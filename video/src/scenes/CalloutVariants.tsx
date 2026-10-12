import React from 'react';
import {AbsoluteFill, Img, staticFile} from 'remotion';
import {Caption, Marker} from '../lib/Paper';
import tokens from '../../style/tokens.json';

// Static options for the callout look (Geoff, 2026-10-11: the hand-drawn circles "feel a little sloppy and
// amateur"). All on the same real frame: S3's Needs you card, "waiting for your input". Geoff picks one.

const W = tokens.frame.width, H = tokens.frame.height, ACCENT = tokens.callout.accent;
const SRC = 'capture/video-s3-list.png', SCALE = 4;
const VIEW = {x: 1080, y: 10, w: 720, h: 405};          // window points the frame shows
const EL = {x: 1477, y: 82, w: 307, h: 126};            // the card (video.s3.needs.1)
const k = W / VIEW.w;
const R = {x: (EL.x - VIEW.x) * k, y: (EL.y - VIEW.y) * k, w: EL.w * k, h: EL.h * k};

const Picture = ({dim = 0}: {dim?: number}) => (
  <AbsoluteFill style={{overflow: 'hidden', background: '#fff'}}>
    <Img src={staticFile(SRC)} style={{position: 'absolute', left: -VIEW.x * k, top: -VIEW.y * k, transformOrigin: '0 0', transform: `scale(${k / SCALE})`, maxWidth: 'none'}} />
    {dim > 0 && <AbsoluteFill style={{background: `rgba(15,17,20,${dim})`}} />}
  </AbsoluteFill>
);
const pad = 14;
const box = (p = pad) => ({left: R.x - p, top: R.y - p, width: R.w + 2 * p, height: R.h + 2 * p});

/** A · today: the hand-drawn marker. */
const Marked = () => (<><Picture /><Marker cx={R.x + R.w / 2} cy={R.y + R.h / 2} rx={R.w / 2 + 18} ry={R.h / 2 + 14} progress={1} /></>);

/** B · ring: a crisp rounded outline in the accent, with a soft halo. Draws on as a sweep. */
const Ring = () => (<><Picture />
  <div style={{position: 'absolute', ...box(), borderRadius: 18, border: `4px solid ${ACCENT}`, boxShadow: `0 0 0 8px rgba(47,111,235,0.16), 0 10px 30px rgba(47,111,235,0.18)`}} /></>);

/** C · spotlight: everything else dims; the card stays lit with a thin white edge. */
const Spotlight = () => (<><Picture />
  <div style={{position: 'absolute', ...box(), borderRadius: 18, boxShadow: '0 0 0 4000px rgba(15,17,20,0.52), 0 0 0 2px rgba(255,255,255,0.95)'}} /></>);

/** D · lift: the card itself rises toward the viewer, a little larger, with a deep shadow; the rest dims slightly. */
const Lift = () => {
  const s = 1.08, cx = R.x + R.w / 2, cy = R.y + R.h / 2;
  return (<><Picture dim={0.28} />
    <div style={{position: 'absolute', left: cx - (R.w * s) / 2, top: cy - (R.h * s) / 2, width: R.w * s, height: R.h * s, borderRadius: 16, overflow: 'hidden',
      boxShadow: '0 30px 70px rgba(0,0,0,0.38), 0 0 0 3px rgba(47,111,235,0.9)'}}>
      <Img src={staticFile(SRC)} style={{position: 'absolute', left: -EL.x * k * s, top: -EL.y * k * s, transformOrigin: '0 0', transform: `scale(${(k * s) / SCALE})`, maxWidth: 'none'}} />
    </div></>);
};

/** E · brackets: four corner marks frame the card, like a camera's focus frame. */
const Brackets = () => {
  const b = box(16), L = 36, t = 5;
  const corner = (x: number, y: number, sx: number, sy: number) => (
    <div style={{position: 'absolute', left: x, top: y, width: L, height: L, borderColor: ACCENT, borderStyle: 'solid', borderRadius: 4,
      borderWidth: `${sy < 0 ? t : 0}px ${sx > 0 ? t : 0}px ${sy > 0 ? t : 0}px ${sx < 0 ? t : 0}px`}} />);
  return (<><Picture />
    {corner(b.left, b.top, -1, -1)}{corner(b.left + b.width - L, b.top, 1, -1)}
    {corner(b.left, b.top + b.height - L, -1, 1)}{corner(b.left + b.width - L, b.top + b.height - L, 1, 1)}</>);
};

const VARIANTS: Record<string, () => React.ReactElement> = {marker: Marked, ring: Ring, spotlight: Spotlight, lift: Lift, brackets: Brackets};
export const CalloutVariant = ({variant}: {variant: string}) => {
  const V = VARIANTS[variant] ?? Ring;
  return <AbsoluteFill><V /><Caption text="waiting for your input" /></AbsoluteFill>;
};
