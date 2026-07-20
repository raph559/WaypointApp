import { useEffect, useState } from "react";

const links = {
  download: "https://github.com/raph559/WaypointApp/releases/latest",
  github: "https://github.com/raph559/WaypointApp",
  setup: "https://github.com/raph559/WaypointApp#first-time-setup",
  localDevVPN: "https://apps.apple.com/app/id6755608044",
  contributing:
    "https://github.com/raph559/WaypointApp/blob/main/CONTRIBUTING.md",
  security: "https://github.com/raph559/WaypointApp/blob/main/SECURITY.md",
  license: "https://github.com/raph559/WaypointApp/blob/main/LICENSE",
};

const iconUrl = `${import.meta.env.BASE_URL}waypoint-icon.png`;
const markUrl = `${import.meta.env.BASE_URL}waypoint-mark.png`;

const capabilities = [
  {
    title: "Pick any place.",
    body: "Search, tap the map, or drag the pin.",
  },
  {
    title: "Start. Then move.",
    body: "Change location without restarting the simulation.",
  },
  {
    title: "Know when it stops.",
    body: "Optional local alerts warn when confirmation is lost.",
  },
];

const connectionModes = {
  wifi: {
    label: "Wi-Fi",
    status: "Recommended",
    title: "Start right from the map.",
    body: "Choose a location and tap Start spoofing.",
  },
  cellular: {
    label: "Mobile data",
    status: "Experimental",
    title: "Use the guided handoff.",
    body: "Keep Wi-Fi off and follow the two Airplane Mode prompts.",
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
      { threshold: 0.1, rootMargin: "0px 0px -6% 0px" },
    );

    elements.forEach((element) => {
      if (element.getBoundingClientRect().top < window.innerHeight * 0.98) {
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
              Pick a location and control iOS location simulation directly from
              your iPhone.
            </p>

            <div className="hero-actions">
              <a className="button button-primary" href={links.download}>
                Download IPA
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

        <section className="section feature-section" id="features">
          <div className="section-inner" data-reveal>
            <div className="feature-overview">
              <header className="section-heading">
                <p className="section-kicker">How it works</p>
                <h2>Everything happens on the map.</h2>
              </header>

              <div className="capability-list">
                {capabilities.map((capability, index) => (
                  <article
                    className="capability"
                    key={capability.title}
                    style={{ "--item-delay": `${index * 70}ms` }}
                  >
                    <span className="capability-index" aria-hidden="true">
                      {String(index + 1).padStart(2, "0")}
                    </span>
                    <div>
                      <h3>{capability.title}</h3>
                      <p>{capability.body}</p>
                    </div>
                  </article>
                ))}
              </div>
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
                    data-mode={key}
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

        <section className="section setup-section" id="setup">
          <div className="section-inner setup-inner" data-reveal>
            <div>
              <p className="section-kicker">One-time setup</p>
              <h2>Before the first start.</h2>
              <p className="setup-copy">
                Enable Developer Mode, add your iPhone&apos;s pairing record,
                and install <a href={links.localDevVPN}>LocalDevVPN</a>. After
                that, Waypoint runs on-device—without an account or analytics.
              </p>

              <ul className="setup-facts" aria-label="Requirements">
                <li>iOS 26</li>
                <li>Developer Mode</li>
                <li>LocalDevVPN required</li>
                <li>Mobile data experimental</li>
              </ul>
            </div>

            <div className="setup-actions">
              <a className="button button-primary" href={links.download}>
                Download IPA
              </a>
              <a className="button button-secondary" href={links.setup}>
                Setup guide
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
          <a href={links.github}>Source</a>
          <a href={links.contributing}>Contributing</a>
          <a href={links.security}>Security</a>
          <a href={links.license}>GNU AGPL v3</a>
        </nav>
      </footer>
    </div>
  );
}
