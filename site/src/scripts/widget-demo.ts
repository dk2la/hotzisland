// The hero widget demo: a scripted loop that drags, docks, opens and resizes
// the CSS-built widget in WidgetStage.astro, plus real dragging and clicking.
//
// - The loop (A2) starts on load, pauses while the stage is off screen or the
//   tab is hidden, and stops for good on the first pointer down or key press
//   on the widget.
// - Every position is derived from the stage size, so the same loop runs at
//   any width; a stage resize restarts it. Once the visitor has taken over, a
//   resize only refits the widget and panel into the new bounds.
// - With prefers-reduced-motion there is no loop and no cursor: the widget
//   rests docked right with the panel open. Dragging and clicking still work.

type Edge = 'left' | 'right' | 'top' | 'bottom';
type Orientation = 'v' | 'h';
type Side = 'l' | 'r' | 't' | 'b';

/** Widget metrics in px, from WidgetMetrics in the app. */
const TOP = 24; // menu bar height
const INSET = 6; // gap between a docked strip and the stage edge
const GAP = 8; // gap between the strip and its panel
const M = 10; // margin the panel keeps from the stage edges
const T = 44; // strip thickness
const L = 236; // strip length
const SNAP = 56; // a drop this close to an edge docks to it

const EASE_OUT = 'cubic-bezier(.23,1,.32,1)';
const SPRING_EVENT_MS = 350;
const SPRING_STATE_MS = 400;

/** Thrown inside the loop when it has been superseded or stopped. */
const STALE = Symbol('stale');

export function initWidgetDemo(): void {
  const stage = document.getElementById('stage');
  const widget = document.getElementById('widget');
  const strip = document.getElementById('strip');
  const panel = document.getElementById('panel');
  const cursor = document.getElementById('cursor');
  const calCell = document.getElementById('cell-cal');
  const hint = document.getElementById('hint-text');
  if (!stage || !widget || !strip || !panel || !cursor || !calCell || !hint) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const reduced = () => reducedMotion.matches;

  const rootStyle = getComputedStyle(document.documentElement);
  const token = (name: string) => rootStyle.getPropertyValue(name).trim();
  const EASE_IN_OUT = token('--ease-in-out');
  const SPRING_EVENT = token('--spring-event');
  const SPRING_STATE = token('--spring-state');

  let W = 0; // stage width
  let H = 0; // stage height
  let run = 0; // bumped to cancel the running loop
  let taken = false; // the visitor has taken over: the loop never restarts
  let onscreen = true;

  const st = {
    x: 0,
    y: 0,
    edge: 'right' as Edge | null,
    o: 'v' as Orientation,
    open: false,
    pw: 0,
    ph: 0,
  };

  const clamp = (n: number, min: number, max: number) => Math.max(min, Math.min(max, n));
  /** Strip size [width, height] in the current orientation. */
  const stripSize = (): [number, number] => (st.o === 'v' ? [T, L] : [L, T]);

  /** Panel sizes for this stage: small and big, width and height. */
  function sizes() {
    const bw = W - T - INSET - GAP - M;
    const bh = H - TOP - 2 * M;
    return {
      sw: Math.min(288, Math.round(bw * 0.82)),
      sh: Math.min(236, bh),
      bw: Math.min(372, bw),
      bh: Math.min(352, bh),
    };
  }

  function move(x: number, y: number, duration = 0, easing = 'linear'): void {
    x = Math.round(x);
    y = Math.round(y);
    widget!.style.transition = duration && !reduced() ? `transform ${duration}ms ${easing}` : 'none';
    widget!.style.transform = `translate3d(${x}px,${y}px,0)`;
    st.x = x;
    st.y = y;
  }

  function dockPosition(edge: Edge, along: number): [number, number] {
    const [sw, sh] = stripSize();
    if (edge === 'right') return [W - sw - INSET, clamp(along, TOP + INSET, H - sh - INSET)];
    if (edge === 'left') return [INSET, clamp(along, TOP + INSET, H - sh - INSET)];
    if (edge === 'top') return [clamp(along, INSET, W - sw - INSET), TOP + INSET];
    return [clamp(along, INSET, W - sw - INSET), H - sh - INSET];
  }

  /** A6: switch between column and row around the strip's centre. */
  function setOrientation(o: Orientation, mask: boolean): void {
    if (o === st.o) return;
    const cx = st.x + stripSize()[0] / 2;
    const cy = st.y + stripSize()[1] / 2;
    st.o = o;
    widget!.dataset.o = o;
    st.x = cx - stripSize()[0] / 2;
    st.y = cy - stripSize()[1] / 2;
    if (mask && !reduced() && typeof strip!.animate === 'function') {
      strip!.animate(
        [
          { opacity: 0, transform: 'scale(.96)' },
          { opacity: 1, transform: 'scale(1)' },
        ],
        { duration: 220, easing: EASE_OUT },
      );
    }
  }

  /** A3: spring to the given edge. */
  function settle(edge: Edge): void {
    const o: Orientation = edge === 'top' || edge === 'bottom' ? 'h' : 'v';
    setOrientation(o, true);
    st.edge = edge;
    const [x, y] = dockPosition(edge, o === 'v' ? st.y : st.x);
    move(x, y, SPRING_EVENT_MS, SPRING_EVENT);
  }

  /** The side of the strip the panel opens on. */
  function panelSide(): Side {
    if (st.edge === 'left') return 'r';
    if (st.edge === 'right') return 'l';
    if (st.edge === 'top') return 'b';
    if (st.edge === 'bottom') return 't';
    if (st.o === 'v') return st.x + T / 2 < W / 2 ? 'r' : 'l';
    return st.y + T / 2 < H / 2 ? 'b' : 't';
  }

  /** Room for the panel on that side: [width, height]. */
  function available(side: Side): [number, number] {
    const [sw, sh] = stripSize();
    if (side === 'r') return [W - (st.x + sw + GAP) - M, H - TOP - 2 * M];
    if (side === 'l') return [st.x - GAP - M, H - TOP - 2 * M];
    if (side === 'b') return [W - 2 * M, H - (st.y + sh + GAP) - M];
    return [W - 2 * M, st.y - GAP - TOP - M];
  }

  /** A5 when a duration is given: the one layout animation on the page. */
  function setSize(pw: number, ph: number, duration = 0, easing = 'linear'): void {
    const [aw, ah] = available(panel!.dataset.side as Side);
    st.pw = Math.max(120, Math.min(pw, aw));
    st.ph = Math.max(100, Math.min(ph, ah));
    panel!.style.setProperty('--rs-d', `${duration && !reduced() ? duration : 0}ms`);
    panel!.style.setProperty('--rs-e', easing);
    panel!.style.width = `${st.pw}px`;
    panel!.style.height = `${st.ph}px`;
  }

  /**
   * A4. maxW/maxH: the largest size the panel will reach while open, so it
   * never has to shift.
   */
  function openPanel(pw: number, ph: number, maxW = pw, maxH = ph): void {
    const side = panelSide();
    const [sw, sh] = stripSize();
    const [aw, ah] = available(side);
    panel!.dataset.side = side;
    maxW = Math.min(maxW, aw);
    maxH = Math.min(maxH, ah);
    const s = panel!.style;
    s.left = s.right = s.top = s.bottom = 'auto';
    if (side === 'r' || side === 'l') {
      s[side === 'r' ? 'left' : 'right'] = `${sw + GAP}px`;
      s.top = `${clamp(st.y, TOP + M, H - maxH - M) - st.y}px`;
    } else {
      s[side === 'b' ? 'top' : 'bottom'] = `${sh + GAP}px`;
      s.left = `${clamp(st.x + sw / 2 - maxW / 2, M, W - maxW - M) - st.x}px`;
    }
    setSize(pw, ph);
    void panel!.offsetWidth; // commit the closed state before opening
    panel!.classList.add('open');
    calCell!.classList.add('active'); // data never tweens: the wash jumps
    strip!.setAttribute('aria-expanded', 'true');
    st.open = true;
  }

  function closePanel(): void {
    panel!.classList.remove('open');
    calCell!.classList.remove('active');
    strip!.setAttribute('aria-expanded', 'false');
    st.open = false;
  }

  /** Top-left corner of the open panel in stage coordinates. */
  function panelBox(): [number, number] {
    const [sw, sh] = stripSize();
    const side = panel!.dataset.side as Side;
    let x: number;
    let y: number;
    if (side === 'r') x = st.x + sw + GAP;
    else if (side === 'l') x = st.x - GAP - st.pw;
    else x = st.x + parseFloat(panel!.style.left);
    if (side === 'b') y = st.y + sh + GAP;
    else if (side === 't') y = st.y - GAP - st.ph;
    else y = st.y + parseFloat(panel!.style.top);
    return [x, y];
  }

  const cur = { x: 0, y: 0 };

  function cursorTo(x: number, y: number, duration = 0, easing = 'linear'): void {
    cursor!.style.transition = `transform ${duration}ms ${easing}, opacity 200ms ease-out`;
    cursor!.style.transform = `translate3d(${Math.round(x)}px,${Math.round(y)}px,0)`;
    cur.x = x;
    cur.y = y;
  }

  function cursorShow(on: boolean): void {
    cursor!.style.opacity = on ? '1' : '0';
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

  /** Where the fake cursor grabs the strip. */
  function gripPoint(): [number, number] {
    return st.o === 'v' ? [st.x + T / 2 - 3, st.y + 11] : [st.x + 11, st.y + T / 2 - 3];
  }

  /** A3, scripted: the cursor picks the strip up, carries it, drops it. */
  async function dragTo(tx: number, ty: number, edge: Edge | null, id: number): Promise<void> {
    const [gx, gy] = gripPoint();
    cursorShow(true);
    cursorTo(gx, gy, 520, EASE_IN_OUT);
    await wait(560, id);
    widget!.classList.add('held');
    await wait(160, id);
    const dx = tx - st.x;
    const dy = ty - st.y;
    move(tx, ty, 900, EASE_IN_OUT);
    cursorTo(cur.x + dx, cur.y + dy, 900, EASE_IN_OUT);
    await wait(940, id);
    widget!.classList.remove('held');
    if (edge) settle(edge);
    else st.edge = null;
    await wait(260, id);
    cursorShow(false);
    await wait(240, id);
  }

  /** Rest state: docked right, panel open. Also the reduced-motion state. */
  function reset(): void {
    closePanel();
    cursorShow(false);
    widget!.classList.remove('held');
    st.o = 'v';
    widget!.dataset.o = 'v';
    st.edge = 'right';
    const [x, y] = dockPosition('right', TOP + (H - TOP - L) * 0.22);
    move(x, y);
    cursorTo(W * 0.5, H * 0.62);
    const z = sizes();
    openPanel(z.sw, z.sh);
    hint!.textContent = 'Live · drag the widget';
  }

  /** A2: the demo loop, about 17s per pass. */
  async function loop(id: number): Promise<void> {
    try {
      for (;;) {
        const z = sizes();
        await wait(2600, id);
        closePanel();
        await wait(320, id);

        // Float somewhere free.
        await dragTo(W < 480 ? 18 : W * 0.14, TOP + (H - TOP - L) * 0.5, null, id);
        openPanel(z.sw, z.sh, z.bw, z.bh);
        await wait(1000, id);

        // Resize: width, then height.
        const [bx, by] = panelBox();
        const w0 = st.pw;
        const h0 = st.ph;
        cursorShow(true);
        cursorTo(bx + w0 - 5, by + h0 / 2 - 4, 420, EASE_IN_OUT);
        await wait(460, id);
        setSize(z.bw, h0, 700, EASE_IN_OUT);
        cursorTo(bx + st.pw - 5, cur.y, 700, EASE_IN_OUT);
        await wait(760, id);
        cursorTo(bx + st.pw / 2 - 3, by + h0 - 6, 420, EASE_IN_OUT);
        await wait(460, id);
        setSize(z.bw, z.bh, 700, EASE_IN_OUT);
        cursorTo(cur.x, by + st.ph - 6, 700, EASE_IN_OUT);
        await wait(760, id);
        cursorShow(false);
        await wait(1500, id);
        closePanel();
        await wait(320, id);

        // Dock to the top edge: the strip turns horizontal.
        await dragTo(W / 2 - T / 2, TOP + INSET + 12, 'top', id);
        openPanel(z.sw, z.sh);
        await wait(1700, id);
        closePanel();
        await wait(320, id);

        // Back to the right edge.
        await dragTo(W - L - INSET - 8, TOP + (H - TOP) * 0.34, 'right', id);
        const [x, y] = dockPosition('right', TOP + (H - TOP - L) * 0.22);
        move(x, y, SPRING_STATE_MS, SPRING_STATE);
        await wait(420, id);
        openPanel(z.sw, z.sh);
      }
    } catch (error) {
      if (error !== STALE) throw error;
    }
  }

  function start(): void {
    run++;
    W = stage!.clientWidth;
    H = stage!.clientHeight;
    reset();
    if (!reduced()) void loop(run);
  }

  /** Pin the widget where it is on screen, even mid-transition. */
  function freeze(): void {
    const m = new DOMMatrixReadOnly(getComputedStyle(widget!).transform);
    move(m.m41, m.m42);
  }

  /** The edge the strip is docked to, judged from where it actually is. */
  function edgeHere(): Edge | null {
    if (st.o === 'v') {
      if (st.x < SNAP) return 'left';
      return W - (st.x + T) < SNAP ? 'right' : null;
    }
    if (st.y - TOP < SNAP) return 'top';
    return H - (st.y + T) < SNAP ? 'bottom' : null;
  }

  /** The visitor takes over: stop the loop where it is, for good. */
  function takeOver(): void {
    if (taken) return;
    taken = true;
    run++;
    cursorShow(false);
    widget!.classList.remove('held');
    // The loop only commits st.x/y/edge once a carry lands, so read them back
    // from the screen: the panel must open on a side that has room.
    freeze();
    st.edge = edgeHere();
  }

  /** After a takeover: keep the visitor's state, fitted to the new stage. */
  function refit(): void {
    W = stage!.clientWidth;
    H = stage!.clientHeight;
    const [sw, sh] = stripSize();
    if (st.edge && !drag?.moved) {
      const [x, y] = dockPosition(st.edge, st.o === 'v' ? st.y : st.x);
      move(x, y);
    } else {
      move(clamp(st.x, 2, W - sw - 2), clamp(st.y, TOP + 2, H - sh - 2));
    }
    if (drag && !drag.moved) {
      drag.ox = st.x;
      drag.oy = st.y;
    }
    if (st.open) openPanel(st.pw, st.ph);
  }

  /** The stage or the motion preference changed. */
  function restart(): void {
    if (taken) refit();
    else start();
  }

  function togglePanel(): void {
    if (st.open) {
      closePanel();
      return;
    }
    const z = sizes();
    openPanel(z.bw, z.sh + 40);
  }

  // ---------- visitor drag (pointer capture, 4px threshold) ----------

  let drag: {
    id: number;
    sx: number;
    sy: number;
    ox: number;
    oy: number;
    moved: boolean;
  } | null = null;

  strip.addEventListener('pointerdown', (e) => {
    if (e.button) return;
    takeOver();
    freeze();
    try {
      strip.setPointerCapture(e.pointerId);
    } catch {
      // Capture is best effort (it can fail for synthetic events).
    }
    drag = { id: e.pointerId, sx: e.clientX, sy: e.clientY, ox: st.x, oy: st.y, moved: false };
  });

  strip.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.sx;
    const dy = e.clientY - drag.sy;
    if (!drag.moved) {
      if (Math.abs(dx) + Math.abs(dy) < 4) return;
      drag.moved = true;
      closePanel();
      widget.classList.add('held');
    }
    const [sw, sh] = stripSize();
    // Follows the pointer 1:1, no transition.
    move(clamp(drag.ox + dx, 2, W - sw - 2), clamp(drag.oy + dy, TOP + 2, H - sh - 2));
  });

  function endDrag(e: PointerEvent): void {
    if (!drag || e.pointerId !== drag.id) return;
    const d = drag;
    drag = null;
    widget!.classList.remove('held');
    if (!d.moved) {
      if (e.type === 'pointerup') togglePanel();
      return;
    }
    const [sw, sh] = stripSize();
    const distance: Record<Edge, number> = {
      left: st.x,
      right: W - (st.x + sw),
      top: st.y - TOP,
      bottom: H - (st.y + sh),
    };
    const nearest = (Object.keys(distance) as Edge[]).sort((a, b) => distance[a] - distance[b])[0];
    if (distance[nearest] < SNAP) {
      settle(nearest);
      hint!.textContent = 'Docked · click to open';
    } else {
      st.edge = null;
      hint!.textContent = 'Floating · click to open';
    }
  }

  // On window, so a drag still ends when capture failed and the pointer has
  // left the strip; lostpointercapture covers capture being taken away.
  window.addEventListener('pointerup', endDrag);
  window.addEventListener('pointercancel', endDrag);
  strip.addEventListener('lostpointercapture', endDrag);

  strip.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    e.preventDefault();
    if (e.repeat) return;
    takeOver();
    togglePanel();
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
