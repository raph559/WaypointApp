import { useEffect, useState } from "react";

const links = {
  download: "https://github.com/raph559/WaypointApp/releases/latest",
  github: "https://github.com/raph559/WaypointApp",
  setup: "https://github.com/raph559/WaypointApp#first-time-setup",
  privacy: "https://github.com/raph559/WaypointApp#privacy-and-data-flow",
  limitations:
    "https://github.com/raph559/WaypointApp#compatibility-and-limitations",
  localDevVPN: "https://apps.apple.com/app/id6755608044",
  issues: "https://github.com/raph559/WaypointApp/issues",
  contributing:
    "https://github.com/raph559/WaypointApp/blob/main/CONTRIBUTING.md",
  security: "https://github.com/raph559/WaypointApp/blob/main/SECURITY.md",
  license: "https://github.com/raph559/WaypointApp/blob/main/LICENSE",
};

const iconUrl = `${import.meta.env.BASE_URL}waypoint-icon.png`;
const markUrl = `${import.meta.env.BASE_URL}waypoint-mark.png`;

const capabilities = [
  {
    title: "Find a place",
    body: "Use MapKit suggestions, tap anywhere on the map, or drag the pin.",
  },
  {
    title: "Start from the map",
    body: "Waypoint checks pairing, developer support, and LocalDevVPN within the Start flow.",
  },
  {
    title: "Move without restarting",
    body: "Choose a new point and update an active simulation immediately.",
  },
  {
    title: "Stay informed",
    body: "Status feedback and haptics report changes; optional local alerts warn when confirmation is lost.",
  },
];

const requirements = [
  "iPhone on iOS 26 with Developer Mode enabled",
  "Waypoint's unsigned IPA, signed and installed",
  "LocalDevVPN with its VPN permission accepted",
  "A pairing record created for this iPhone",
  "Internet for the initial developer-support download and whenever using MapKit search",
];

const connectionModes = {
  wifi: {
    label: "Wi-Fi",
    status: "Primary path",
    title: "Start directly from the map.",
    body: "Choose a location and tap Start spoofing. Airplane Mode is not required.",
  },
  cellular: {
    label: "Mobile data",
    status: "Experimental",
    title: "Follow the guided handoff.",
    body: "Keep Wi-Fi off and follow the two Airplane Mode prompts. Reliability varies by device and iOS network state.",
  },
};

function useRevealMotion() {
  useEffect(() => {
    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    );

    if (reduceMotion.matches || !("IntersectionObserver" in window)) {
      return undefined;
    }

    const root = document.documentElement;
    const elements = [...document.querySelectorAll("[data-reveal]")];

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
      if (element.getBoundingClientRect().top < window.innerHeight * 0.92) {
        element.classList.add("is-visible");
      } else {
        observer.observe(element);
      }
    });

    return () => {
      observer.disconnect();
      root.classList.remove("motion-ready");
    };
  }, []);
}

export function App() {
  const [connectionMode, setConnectionMode] = useState("wifi");
  const activeMode = connectionModes[connectionMode];

  useRevealMotion();

  return (
    <div className="site-shell" id="top">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>

      <header className="site-header">
        <a className="brand" href="#top" aria-label="Waypoint home">
          <img src={iconUrl} alt="" width="48" height="48" />
          <span>Waypoint</span>
        </a>

        <nav aria-label="Primary navigation">
          <a href="#features">Features</a>
          <a href="#setup">Setup</a>
          <a href={links.github}>GitHub</a>
        </nav>
      </header>

      <main id="main-content" tabIndex="-1">
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-copy">
            <p className="eyebrow">
              <span className="status-dot" aria-hidden="true" />
              Open source <span aria-hidden="true">·</span> Built for iOS 26
            </p>

            <h1 id="hero-title">
              Your iPhone.
              <br />
              Any place.
            </h1>

            <p className="hero-description">
              Search for a place, tap or drag the pin, then start, move, or stop
              Apple&apos;s developer location simulation from your iPhone.
            </p>

            <div className="hero-actions">
              <a className="button button-primary" href={links.download}>
                Download unsigned IPA
              </a>
              <a className="button button-secondary" href={links.setup}>
                Setup guide
              </a>
            </div>

            <p className="trust-line">
              No jailbreak <span aria-hidden="true">·</span> No JIT
              <span aria-hidden="true">·</span> On-device after setup
            </p>
          </div>

          <div className="hero-mark" aria-hidden="true">
            <img src={markUrl} alt="" width="420" height="460" />
          </div>
        </section>

        <section className="section capability-section" id="features">
          <div className="section-inner" data-reveal>
            <header className="section-heading">
              <p className="section-kicker">What you can do</p>
              <h2>A map, a pin, and direct control.</h2>
            </header>

            <div className="capability-grid">
              {capabilities.map((capability) => (
                <article className="capability" key={capability.title}>
                  <h3>{capability.title}</h3>
                  <p>{capability.body}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section setup-section" id="setup">
          <div className="section-inner setup-layout" data-reveal>
            <header className="section-heading setup-heading">
              <p className="section-kicker">Setup and connections</p>
              <h2>Everything needed before the first start.</h2>
              <p className="section-intro">
                It takes a few device-specific pieces because Waypoint controls
                an Apple developer service. Normal use stays on the iPhone.
              </p>
              <a className="text-link" href={links.setup}>
                Read the complete setup guide
              </a>
            </header>

            <div className="setup-details">
              <ol className="requirement-list" role="list">
                {requirements.map((requirement, index) => (
                  <li key={requirement}>
                    <span aria-hidden="true">
                      {String(index + 1).padStart(2, "0")}
                    </span>
                    <p>{requirement}</p>
                  </li>
                ))}
              </ol>

              <p className="setup-note">
                SideStore is optional and is not a runtime dependency.
                <a href={links.localDevVPN}> LocalDevVPN</a> is required by the
                current architecture.
              </p>
            </div>

            <div className="connection-switcher">
              <div
                className="mode-tabs"
                role="group"
                aria-label="Connection mode"
              >
                {Object.entries(connectionModes).map(([key, mode]) => (
                  <button
                    aria-controls="connection-panel"
                    aria-pressed={connectionMode === key}
                    className="mode-tab"
                    id={`${key}-tab`}
                    key={key}
                    onClick={() => setConnectionMode(key)}
                    type="button"
                  >
                    <span>{mode.label}</span>
                    <small>{mode.status}</small>
                  </button>
                ))}
              </div>

              <div
                aria-atomic="true"
                aria-live="polite"
                className="connection-panel"
                id="connection-panel"
                key={connectionMode}
              >
                <p>{activeMode.status}</p>
                <h3>{activeMode.title}</h3>
                <p>{activeMode.body}</p>
              </div>
            </div>
          </div>
        </section>

        <section className="section assurance-section" id="privacy">
          <div className="section-inner" data-reveal>
            <header className="section-heading assurance-heading">
              <p className="section-kicker">Private, open, honest</p>
              <h2>No account. No analytics. No Waypoint-operated server.</h2>
            </header>

            <div className="assurance-grid">
              <article className="assurance-item">
                <p className="assurance-label">Your pairing record</p>
                <h3>Protected on your iPhone.</h3>
                <p>
                  After import, it is stored with iOS file protection and excluded
                  from backups. Treat it like a secret and never share it.
                </p>
                <a className="text-link text-link-light" href={links.privacy}>
                  Privacy and data flow
                </a>
              </article>

              <article
                className="assurance-item"
                id="limitations"
              >
                <p className="assurance-label">Before you rely on it</p>
                <h3>Simulation remains detectable.</h3>
                <p>
                  Apps can reject a simulated location or compare it with other
                  signals. Wi-Fi is the primary path; mobile-data start remains
                  experimental.
                </p>
                <a
                  className="text-link text-link-light"
                  href={links.limitations}
                >
                  Compatibility details
                </a>
              </article>
            </div>

            <div className="architecture-note">
              <p>How it connects</p>
              <p>
                Waypoint uses idevice and LocalDevVPN to reach Apple&apos;s DVT
                LocationSimulation service, which feeds Core Location apps.
              </p>
            </div>
          </div>
        </section>

        <section className="cta-section">
          <div className="section-inner cta-inner" data-reveal>
            <div>
              <p className="section-kicker">Open source · GNU AGPL v3</p>
              <h2>Download it or inspect every line.</h2>
              <p>
                Compatibility reports, reproducible bugs, and focused pull
                requests are welcome.
              </p>
            </div>

            <div className="hero-actions cta-actions">
              <a className="button button-primary" href={links.download}>
                Download unsigned IPA
              </a>
              <a className="button button-secondary" href={links.github}>
                View source
              </a>
            </div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="footer-brand">
          <img src={iconUrl} alt="" width="36" height="36" />
          <span>Waypoint</span>
        </div>
        <nav aria-label="Footer navigation">
          <a href={links.contributing}>Contributing</a>
          <a href={links.security}>Security</a>
          <a href={links.license}>GNU AGPL v3</a>
        </nav>
      </footer>
    </div>
  );
}
