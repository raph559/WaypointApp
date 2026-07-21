import { useEffect } from "react";

export function useHeroParallax(imageRef) {
  useEffect(() => {
    const artwork = imageRef.current;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    if (reduceMotion.matches || !artwork) return undefined;

    let frame = null;

    const update = () => {
      frame = null;
      const progress = Math.min(
        Math.max(window.scrollY / Math.max(window.innerHeight, 1), 0),
        1.25,
      );
      artwork.style.setProperty("--art-shift", `${progress * 22}px`);
      artwork.style.setProperty("--art-scale", `${1 - progress * 0.018}`);
    };

    const requestUpdate = () => {
      if (frame !== null) return;
      frame = window.requestAnimationFrame(update);
    };

    update();
    window.addEventListener("scroll", requestUpdate, { passive: true });
    window.addEventListener("resize", requestUpdate);

    return () => {
      if (frame !== null) window.cancelAnimationFrame(frame);
      window.removeEventListener("scroll", requestUpdate);
      window.removeEventListener("resize", requestUpdate);
      artwork.style.removeProperty("--art-shift");
      artwork.style.removeProperty("--art-scale");
    };
  }, [imageRef]);
}
