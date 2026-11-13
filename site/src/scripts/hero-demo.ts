// The hero demo: the selected widget on the picture in Hero.astro.
//
// - The widget stays in place and switches tabs. The tabs are screenshots
//   stacked in the same box: the first is the static image, the others are
//   downloaded and decoded after the page has loaded, then faded in one after
//   another. Just before each switch the strip icon about to be "clicked"
//   lights up. Only opacity and transform change.
// - The switching runs only while the picture is on screen, the browser tab
//   is visible and the visitor is not moving the widget. It picks up where it
//   stopped.
// - The visitor can drag the widget, or move it with the arrow keys. Its
//   placement is two numbers, x and y (offset in px from its resting place),
//   written to custom properties on `.sel`; the CSS turns them into
//   transforms. A resize refits the placement into the new bounds.
// - With prefers-reduced-motion nothing switches and nothing is downloaded:
//   the first screenshot stays. Dragging still works, without the docking
//   glide.

/** The outline sits this many px outside the panel. Mirrors Hero.astro. */
const PAD = 4;
/** Gap between a docked widget and the picture's edge. */
const INSET = 8;
/** A drop this close to an edge docks to it. */
const SNAP = 28;
/** Arrow key step in px; with Shift it is three times that. */
const KEY_STEP = 16;

/** How long each tab is shown. */
const HOLD = 2800;
/** The press cue starts this long before the switch. */
const PRESS_LEAD = 200;
/** The crossfade. Mirrors Hero.astro. */
const FADE = 160;
/** The soonest a switch may follow the visitor letting go of the widget. */
const AFTER_MOVE = 1000;
/** The soonest a switch may follow the picture coming back on screen. */
const AFTER_PAUSE = 600;

interface Tab {
  /** The stacked screenshot; null for the first tab, which is the static image. */
  el: HTMLElement | null;
  /** Where the tab's strip icon is: a CSS `top` for the press cue. */
  press: string;
  state: 'idle' | 'loading' | 'ready' | 'failed';
}

export function initHeroDemo(): void {
  const stage = document.getElementById('stage');
  const sel = document.getElementById('sel');
  const first = sel?.querySelector<HTMLElement>('.sel__shots');
  const cue = sel?.querySelector<HTMLElement>('.sel__press');
  if (!stage || !sel || !first) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const reduced = () => reducedMotion.matches;
  const clamp = (n: number, min: number, max: number) => Math.max(min, Math.min(max, n));

  // ---------- tabs ----------

  const tabs: Tab[] = [
    { el: null, press: first.dataset.press ?? '', state: 'ready' },
    ...Array.from(sel.querySelectorAll<HTMLElement>('.sel__shot'), (el): Tab => {
      return { el, press: el.dataset.press ?? '', state: 'idle' };
    }),
  ];

  let current = 0; // the tab on show
  let pageLoaded = document.readyState === 'complete';
  let onscreen = true;
  let running = false;
  let timer = 0;
  let settleTimer = 0;
  let dueAt = 0; // when the next switch is due
  let remaining = HOLD; // what was left of the hold when the switching paused

  /** Download and decode the stacked screenshots. Once. */
  function load(): void {
    for (const tab of tabs) {
      const img = tab.el?.querySelector('img');
      if (!tab.el || !img || tab.state !== 'idle') continue;
      tab.state = 'loading';
      tab.el.querySelectorAll('source').forEach((source) => {
        source.srcset = source.dataset.srcset ?? '';
      });
      img.src = img.dataset.src ?? '';
      // Decoded before it is ever shown, so the fade never starts on a blank.
      img.decode().then(
        () => (tab.state = 'ready'),
        () => (tab.state = 'failed'),
      );
    }
  }

  /** The tab after the current one, skipping any that failed to load. */
  function nextTab(): number {
    for (let step = 1; step < tabs.length; step++) {
      const i = (current + step) % tabs.length;
      if (tabs[i].state !== 'failed') return i;
    }
    return current;
  }

  /** The state after a fade: only the current tab is on. */
  function settle(): void {
    window.clearTimeout(settleTimer);
    tabs.forEach((tab, i) => {
      tab.el?.classList.remove('is-top', 'is-off');
      tab.el?.classList.toggle('is-on', i === current);
    });
  }

  function show(next: number): void {
    settle();
    const from = tabs[current].el;
    const to = tabs[next].el;
    if (to) {
      // Fades in over whatever is showing.
      to.classList.add('is-on', 'is-top');
    } else if (from) {
      // Back to the static image, which lies under everything: fade out.
      from.classList.add('is-off');
      from.classList.remove('is-on');
    }
    current = next;
    settleTimer = window.setTimeout(settle, FADE + 40);
  }

  /** Light up the strip icon at `top`. */
  function press(top: string): void {
    if (!cue || !top) return;
    cue.style.setProperty('--press', top);
    // Restart the CSS animation: drop the class, flush styles, add it back.
    cue.classList.remove('is-on');
    void cue.offsetWidth;
    cue.classList.add('is-on');
  }

  /** Schedule the next switch `ms` from now. */
  function arm(ms: number): void {
    dueAt = performance.now() + ms;
    window.clearTimeout(timer);
    timer = window.setTimeout(() => {
      const next = nextTab();
      if (next === current) return; // nothing else to show
      if (tabs[next].state !== 'ready') return arm(PRESS_LEAD + 300); // still loading
      press(tabs[next].press);
      timer = window.setTimeout(() => {
        show(next);
        arm(HOLD);
      }, PRESS_LEAD);
    }, Math.max(0, ms - PRESS_LEAD));
  }

  const shouldRun = () =>
    pageLoaded && onscreen && !document.hidden && !drag && !reduced() && tabs.length > 1;

  function pause(): void {
    if (!running) return;
    running = false;
    window.clearTimeout(timer);
    remaining = Math.max(0, dueAt - performance.now());
  }

  /** Carry on if nothing stands in the way; the next switch is at least `delay` away. */
  function resume(delay = 0): void {
    if (running || !shouldRun()) return;
    running = true;
    load();
    arm(Math.max(remaining, delay));
  }

  // ---------- placement ----------

  let W = 0; // picture width
  let H = 0; // picture height
  // The widget's resting box inside the picture.
  const base = { l: 0, t: 0, w: 0, h: 0 };
  // Offset from the resting place.
  const st = { x: 0, y: 0 };
  let moved = false; // the visitor has placed the widget
  let glide = 0; // bumped to cancel a docking glide

  function measure(): void {
    W = stage!.clientWidth;
    H = stage!.clientHeight;
    base.l = sel!.offsetLeft;
    base.t = sel!.offsetTop;
    base.w = sel!.offsetWidth;
    base.h = sel!.offsetHeight;
  }

  /** Write the placement to the page. */
  function apply(): void {
    sel!.style.setProperty('--x', `${st.x.toFixed(2)}px`);
    sel!.style.setProperty('--y', `${st.y.toFixed(2)}px`);
  }

  // Positions below are in picture coordinates (the screenshot's top-left
  // corner); `st.x`/`st.y` are the same minus the resting place.

  /** Left and top limits that keep the selection and its label inside the picture. */
  const minLeft = PAD + 2;
  const maxLeft = () => W - base.w - 2;
  const minTop = PAD + 2;
  // Room is kept under the widget for the size label (12px gap + 20px + 2px).
  const maxTop = () => H - base.h - 34;

  function clampInto(): void {
    st.x = clamp(st.x + base.l, minLeft, Math.max(minLeft, maxLeft())) - base.l;
    st.y = clamp(st.y + base.t, minTop, Math.max(minTop, maxTop())) - base.t;
  }

  /** The picture changed size: keep the visitor's placement, fitted to it. */
  function refit(): void {
    const oldW = W;
    const oldH = H;
    const left = st.x + base.l;
    const top = st.y + base.t;
    glide++;
    measure();
    if (!moved) {
      st.x = 0;
      st.y = 0;
    } else {
      if (oldW && oldH) {
        st.x = (left * W) / oldW - base.l;
        st.y = (top * H) / oldH - base.t;
      }
      clampInto();
    }
    apply();
    if (drag) {
      // Mid-drag: carry on from the refitted place.
      drag.ox = st.x;
      drag.oy = st.y;
      drag.sx = drag.lx;
      drag.sy = drag.ly;
    }
  }

  /**
   * Dock to the left or right edge if the widget was let go close to one.
   * (Not top or bottom: the widget is nearly as tall as the picture, so it
   * would always count as close to both.)
   */
  function dockIfNear(): void {
    const left = st.x + base.l;
    const toLeft = left - PAD;
    const toRight = W - (left + base.w);
    if (Math.min(toLeft, toRight) >= SNAP) return;

    const from = st.x;
    const to = (toLeft < toRight ? INSET + PAD : W - base.w - INSET) - base.l;
    if (reduced()) {
      st.x = to;
      apply();
      return;
    }
    const id = ++glide;
    let start = 0;
    requestAnimationFrame(function frame(now: number): void {
      if (id !== glide) return; // superseded by a new drag or a resize
      if (!start) start = now;
      const t = Math.min(1, (now - start) / 300);
      st.x = from + (to - from) * (1 - Math.pow(1 - t, 4));
      apply();
      if (t < 1) requestAnimationFrame(frame);
    });
  }

  // ---------- visitor drag ----------

  // sx/sy: where the pointer was when the drag began; ox/oy: the placement
  // then; lx/ly: where the pointer was last seen.
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
    glide++;
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
    pause(); // no tab switches while the widget is held
  });

  sel.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    // Follows the pointer 1:1.
    moved = true;
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
    if (moved) dockIfNear();
    resume(AFTER_MOVE);
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
    glide++;
    moved = true;
    st.x += dx;
    st.y += dy;
    clampInto();
    apply();
    // Hold the tab for a moment after each step.
    pause();
    resume(AFTER_MOVE);
  });

  // ---------- lifecycle ----------

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(
      (entries) => {
        onscreen = entries[entries.length - 1].isIntersecting;
        if (onscreen) resume(AFTER_PAUSE);
        else pause();
      },
      { threshold: 0.1 },
    ).observe(stage);
  }

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) pause();
    else resume(AFTER_PAUSE);
  });

  reducedMotion.addEventListener('change', () => {
    if (reduced()) {
      // Back to the static image.
      pause();
      current = 0;
      remaining = HOLD;
      settle();
    } else {
      resume();
    }
  });

  let lastW = 0;
  let lastH = 0;
  if ('ResizeObserver' in window) {
    // Fires once on observe, which is the first measurement.
    new ResizeObserver(() => {
      if (stage.clientWidth === lastW && stage.clientHeight === lastH) return;
      lastW = stage.clientWidth;
      lastH = stage.clientHeight;
      refit();
    }).observe(stage);
  } else {
    measure();
    window.addEventListener('resize', refit);
  }

  // The other screenshots wait for the page to finish loading.
  if (pageLoaded) {
    resume();
  } else {
    window.addEventListener('load', () => {
      pageLoaded = true;
      resume();
    });
  }
}
