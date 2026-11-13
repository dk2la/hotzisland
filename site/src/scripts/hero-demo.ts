// The hero demo: the selected widget on the picture in Hero.astro.
//
// - A scripted loop drags the widget to another spot, resizes it (the label
//   counts the size) and docks it to the picture's edge. It starts on load,
//   pauses while the picture is off screen or the tab is hidden, and stops
//   for good the first time the visitor grabs the widget or moves it with
//   the arrow keys.
// - The widget's state is three numbers: x and y (offset in px from its
//   resting place) and s (scale). They are written to custom properties on
//   `.sel`; the CSS turns them into transforms. Nothing else is animated.
// - Every position is derived from the picture's size, so the loop runs at
//   any width. A resize restarts the loop; once the visitor has taken over
//   it only refits the widget into the new bounds.
// - With prefers-reduced-motion there is no loop: the widget rests where the
//   design puts it. Dragging still works, without the docking glide.

/** The panel's share of the screenshot's width; the rest is the strip. */
const PANEL = 0.908;
/** The outline sits this many px outside the panel. Mirrors Hero.astro. */
const PAD = 4;
/** Gap between a docked widget and the picture's edge. */
const INSET = 8;
/** A drop this close to an edge docks to it. */
const SNAP = 28;
/** The size the label shows at scale 1. */
const LABEL_W = 420;
const LABEL_H = 640;
/** Scale the loop resizes down to. */
const SMALL = 0.74;
/** Arrow key step in px; with Shift it is three times that. */
const KEY_STEP = 16;

type Ease = (t: number) => number;
const easeInOut: Ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const easeOut: Ease = (t) => 1 - Math.pow(1 - t, 4);

interface State {
  x: number;
  y: number;
  s: number;
}

/** Thrown inside the loop when it has been superseded or stopped. */
const STALE = Symbol('stale');

export function initHeroDemo(): void {
  const stage = document.getElementById('stage');
  const sel = document.getElementById('sel');
  const label = document.getElementById('sel-size');
  if (!stage || !sel || !label) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const reduced = () => reducedMotion.matches;

  let W = 0; // picture width
  let H = 0; // picture height
  // The widget's resting box inside the picture.
  const base = { l: 0, t: 0, w: 0, h: 0 };
  const st: State = { x: 0, y: 0, s: 1 };

  let run = 0; // bumped to cancel the running loop or glide
  let taken = false; // the visitor has taken over: the loop never restarts
  let onscreen = true;
  let labelText = '';

  const clamp = (n: number, min: number, max: number) => Math.max(min, Math.min(max, n));

  function measure(): void {
    W = stage!.clientWidth;
    H = stage!.clientHeight;
    base.l = sel!.offsetLeft;
    base.t = sel!.offsetTop;
    base.w = sel!.offsetWidth;
    base.h = sel!.offsetHeight;
  }

  /** Write the state to the page. */
  function apply(): void {
    const panel = PANEL * base.w;
    const style = sel!.style;
    style.setProperty('--x', `${st.x.toFixed(2)}px`);
    style.setProperty('--y', `${st.y.toFixed(2)}px`);
    style.setProperty('--s', st.s.toFixed(4));
    style.setProperty('--dw', `${(panel * (st.s - 1)).toFixed(2)}px`);
    style.setProperty('--dh', `${(base.h * (st.s - 1)).toFixed(2)}px`);
    style.setProperty('--ex', ((panel * st.s + 2 * PAD) / (panel + 2 * PAD)).toFixed(4));
    style.setProperty('--ey', ((base.h * st.s + 2 * PAD) / (base.h + 2 * PAD)).toFixed(4));
    const text = `${Math.round(LABEL_W * st.s)} × ${Math.round(LABEL_H * st.s)}`;
    if (text !== labelText) {
      labelText = text;
      label!.textContent = text;
    }
  }

  // Positions below are in picture coordinates (the screenshot's top-left
  // corner); `st.x`/`st.y` are the same minus the resting place.

  /** Left and top limits that keep the selection and its label inside the picture. */
  const minLeft = () => PAD + 2;
  const maxLeft = (s: number) => W - base.w * s - 2;
  const minTop = () => PAD + 2;
  // Room is kept under the widget for the size label (12px gap + 20px + 2px).
  const maxTop = (s: number) => H - base.h * s - 34;

  function clampInto(): void {
    st.x = clamp(st.x + base.l, minLeft(), Math.max(minLeft(), maxLeft(st.s))) - base.l;
    st.y = clamp(st.y + base.t, minTop(), Math.max(minTop(), maxTop(st.s))) - base.t;
  }

  /** Resolves after `ms`, later while paused; rejects once the loop is stale. */
  function wait(ms: number, id: number): Promise<void> {
    return new Promise((resolve, reject) => {
      window.setTimeout(function check() {
        if (id !== run) return reject(STALE);
        if (!onscreen || document.hidden) return void window.setTimeout(check, 300);
        resolve();
      }, ms);
    });
  }

  /** Animate the state to `to`. Rejects, leaving the state as it is, once stale. */
  function tween(to: Partial<State>, ms: number, ease: Ease, id: number): Promise<void> {
    const from = { ...st };
    const target = { ...st, ...to };
    return new Promise((resolve, reject) => {
      let start = 0;
      function frame(now: number): void {
        if (id !== run) return reject(STALE);
        if (!start) start = now;
        const t = Math.min(1, (now - start) / ms);
        const k = ease(t);
        st.x = from.x + (target.x - from.x) * k;
        st.y = from.y + (target.y - from.y) * k;
        st.s = from.s + (target.s - from.s) * k;
        apply();
        if (t < 1) requestAnimationFrame(frame);
        else resolve();
      }
      requestAnimationFrame(frame);
    });
  }

  /** The demo loop, about 12s per pass. */
  async function loop(id: number): Promise<void> {
    const X = (left: number) => left - base.l;
    const Y = (top: number) => top - base.t;
    try {
      for (;;) {
        await wait(2400, id);

        // Dragged to another spot and left floating there.
        // (Low enough to read as a move, high enough to keep the label in.)
        const floatTop = Math.min(H * 0.13, maxTop(1));
        await tween({ x: X(Math.max(minLeft(), W * 0.07)), y: Y(floatTop) }, 1000, easeInOut, id);
        await wait(500, id);

        // Resized from the bottom right handle; the label counts.
        await tween({ s: SMALL }, 900, easeInOut, id);
        await wait(700, id);

        // Carried towards the right edge, let go, and it docks.
        const docked = X(W - base.w * SMALL - INSET);
        await tween({ x: docked - 22, y: Y(H * 0.3) }, 1000, easeInOut, id);
        await tween({ x: docked }, 350, easeOut, id);
        await wait(1600, id);

        // Back to full size, still against the edge, then home.
        await tween({ s: 1, x: X(W - base.w - INSET), y: 0 }, 900, easeInOut, id);
        await wait(900, id);
        await tween({ x: 0, y: 0 }, 900, easeInOut, id);
      }
    } catch (error) {
      if (error !== STALE) throw error;
    }
  }

  function start(): void {
    run++;
    measure();
    st.x = 0;
    st.y = 0;
    st.s = 1;
    apply();
    if (!reduced()) void loop(run);
  }

  /** The visitor takes over: the loop stops where it is, for good. */
  function takeOver(): void {
    run++; // also cancels a docking glide
    taken = true;
  }

  /** After a takeover: keep the visitor's placement, fitted to the new size. */
  function refit(): void {
    const oldW = W;
    const oldH = H;
    const left = st.x + base.l;
    const top = st.y + base.t;
    measure();
    if (oldW && oldH) {
      st.x = (left * W) / oldW - base.l;
      st.y = (top * H) / oldH - base.t;
    }
    clampInto();
    apply();
    if (drag) {
      // Mid-drag: carry on from the refitted place.
      drag.ox = st.x;
      drag.oy = st.y;
      drag.sx = drag.lx;
      drag.sy = drag.ly;
    }
  }

  /** The picture or the motion preference changed. */
  function restart(): void {
    if (taken) refit();
    else start();
  }

  /**
   * Dock to the left or right edge if the widget was let go close to one.
   * (Not top or bottom: at full size the widget is nearly as tall as the
   * picture, so it would always count as close to both.)
   */
  function dockIfNear(): void {
    const left = st.x + base.l;
    const toLeft = left - PAD;
    const toRight = W - (left + base.w * st.s);
    if (Math.min(toLeft, toRight) >= SNAP) return;

    const to: Partial<State> = {
      x: (toLeft < toRight ? INSET + PAD : W - base.w * st.s - INSET) - base.l,
    };

    if (reduced()) {
      Object.assign(st, to);
      apply();
      return;
    }
    tween(to, 300, easeOut, run).catch(() => {
      // Superseded by a new drag: the state stays wherever it was.
    });
  }

  // ---------- visitor drag ----------

  // sx/sy: where the pointer was when the drag began; ox/oy: the state then;
  // lx/ly: where the pointer was last seen.
  let drag: {
    id: number;
    sx: number;
    sy: number;
    ox: number;
    oy: number;
    lx: number;
    ly: number;
  } | null = null;

  sel.addEventListener('pointerdown', (e) => {
    if (e.button) return;
    takeOver();
    try {
      sel.setPointerCapture(e.pointerId);
    } catch {
      // Capture is best effort (it can fail for synthetic events).
    }
    drag = {
      id: e.pointerId,
      sx: e.clientX,
      sy: e.clientY,
      ox: st.x,
      oy: st.y,
      lx: e.clientX,
      ly: e.clientY,
    };
    sel.classList.add('is-held');
  });

  sel.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    // Follows the pointer 1:1.
    drag.lx = e.clientX;
    drag.ly = e.clientY;
    st.x = drag.ox + (e.clientX - drag.sx);
    st.y = drag.oy + (e.clientY - drag.sy);
    clampInto();
    apply();
  });

  function endDrag(e: PointerEvent): void {
    if (!drag || e.pointerId !== drag.id) return;
    drag = null;
    sel!.classList.remove('is-held');
    dockIfNear();
  }

  // On window, so a drag still ends when capture failed and the pointer has
  // left the widget; lostpointercapture covers capture being taken away.
  window.addEventListener('pointerup', endDrag);
  window.addEventListener('pointercancel', endDrag);
  sel.addEventListener('lostpointercapture', endDrag);

  sel.addEventListener('keydown', (e) => {
    const step = e.shiftKey ? KEY_STEP * 3 : KEY_STEP;
    let dx = 0;
    let dy = 0;
    if (e.key === 'ArrowLeft') dx = -step;
    else if (e.key === 'ArrowRight') dx = step;
    else if (e.key === 'ArrowUp') dy = -step;
    else if (e.key === 'ArrowDown') dy = step;
    else return;
    e.preventDefault();
    takeOver();
    st.x += dx;
    st.y += dy;
    clampInto();
    apply();
  });

  // ---------- lifecycle ----------

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(
      (entries) => {
        onscreen = entries[entries.length - 1].isIntersecting;
      },
      { threshold: 0.1 },
    ).observe(stage);
  }

  let lastW = 0;
  let lastH = 0;
  if ('ResizeObserver' in window) {
    // Fires once on observe, which is the initial start.
    new ResizeObserver(() => {
      if (stage.clientWidth === lastW && stage.clientHeight === lastH) return;
      lastW = stage.clientWidth;
      lastH = stage.clientHeight;
      restart();
    }).observe(stage);
  } else {
    start();
  }

  reducedMotion.addEventListener('change', restart);
}
