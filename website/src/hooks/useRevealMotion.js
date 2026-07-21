import { useLayoutEffect } from "react";

export function useRevealMotion(rootRef) {
  useLayoutEffect(() => {
    const root = rootRef.current;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    if (
      !root ||
      reduceMotion.matches ||
      !("IntersectionObserver" in window)
    ) {
      return undefined;
    }

    const elements = [...root.querySelectorAll("[data-reveal]")];
    root.classList.add("motion-ready");

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" },
    );

    elements.forEach((element) => {
      if (element.getBoundingClientRect().top < window.innerHeight * 0.96) {
        element.classList.add("is-visible");
      } else {
        observer.observe(element);
      }
    });

    return () => {
      observer.disconnect();
      root.classList.remove("motion-ready");
    };
  }, [rootRef]);
}
