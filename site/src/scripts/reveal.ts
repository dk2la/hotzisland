// A8 scroll reveal and A9 License meters.
//
// Only elements that are below the fold at load are hidden first, so the page
// is complete without script and nothing visible ever blinks out.

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

/** A9: the three segments of each meter switch on one at a time. */
function runMeters(license: HTMLElement): void {
  if (reducedMotion.matches) return; // all on from the start
  const meters = license.querySelectorAll<HTMLElement>('.segs');
  meters.forEach((meter) => {
    const segments = meter.querySelectorAll<HTMLElement>('i');
    segments.forEach((segment, index) => {
      segment.classList.add('off');
      window.setTimeout(() => segment.classList.remove('off'), 250 + index * 140);
    });
  });
}

export function initReveal(): void {
  if (!('IntersectionObserver' in window)) return;
  const license = document.getElementById('license');

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        const el = entry.target as HTMLElement;
        el.classList.remove('rv-wait');
        observer.unobserve(el);
        if (el === license) runMeters(el);
      }
    },
    { threshold: 0.15 },
  );

  document.querySelectorAll<HTMLElement>('[data-reveal]').forEach((el) => {
    if (el.getBoundingClientRect().top > window.innerHeight * 0.9) {
      el.classList.add('rv-wait');
      observer.observe(el);
    }
  });
}
