import { useRef } from "react";
import { SiteFooter } from "./components/SiteFooter.jsx";
import { SiteHeader } from "./components/SiteHeader.jsx";
import { useRevealMotion } from "./hooks/useRevealMotion.js";
import { HeroSection } from "./sections/HeroSection.jsx";
import { JourneySection } from "./sections/JourneySection.jsx";
import { SetupSection } from "./sections/SetupSection.jsx";

export function App() {
  const shellRef = useRef(null);
  useRevealMotion(shellRef);

  return (
    <div className="site-shell" id="top" ref={shellRef}>
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>

      <SiteHeader />

      <main id="main-content" tabIndex="-1">
        <HeroSection />
        <JourneySection />
        <SetupSection />
      </main>

      <SiteFooter />
    </div>
  );
}
