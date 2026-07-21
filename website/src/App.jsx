import { useEffect, useLayoutEffect, useState } from "react";

const links = {
  download:
    "https://github.com/raph559/WaypointApp/releases/latest/download/Waypoint-iOS26-v1.0.3-unsigned.ipa",
  github: "https://github.com/raph559/WaypointApp",
  setup: "#setup",
  fullSetup: "https://github.com/raph559/WaypointApp#first-time-setup",
  sideStore: "https://docs.sidestore.io/docs/installation/install",
  altStore: "https://faq.altstore.io/altstore-classic/altserver",
  localDevVPN: "https://apps.apple.com/app/id6755608044",
  developerMode:
    "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device",
  pairingTool: "https://github.com/jkcoxson/idevice_pair",
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

const setupSteps = [
  {
    title: "Choose an installer.",
    body:
      "Waypoint is an unsigned IPA. Use SideStore or AltStore Classic to sign and install it.",
    actions: [
      { label: "Install SideStore", href: links.sideStore },
      { label: "Use AltStore", href: links.altStore },
    ],
  },
  {
    title: "Prepare your iPhone.",
    body:
      "When your installer prompts you, enable Developer Mode and restart. Install LocalDevVPN and accept its VPN permission once.",
    actions: [
      { label: "Developer Mode help", href: links.developerMode },
      { label: "Get LocalDevVPN", href: links.localDevVPN },
    ],
  },
  {
    title: "Download Waypoint.",
    body: "Get the latest IPA, then open it in SideStore or AltStore to install it.",
    actions: [
      { label: "Download IPA", href: links.download, primary: true },
    ],
  },
  {
    title: "Start and pair on Wi-Fi.",
    body:
      "Choose a location and tap Start spoofing. If asked, import directly from SideStore or select this iPhone's pairing file from Files.",
  },
  {
    title: "Let setup finish.",
    body:
      "Keep Waypoint open and online while it downloads about 17 MB of support files. Wait for Spoof Active. Airplane Mode is not needed.",
  },
];

function useRevealMotion() {
  useLayoutEffect(() => {
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

function useScrollMotion() {
  useEffect(() => {
    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    );
    const mark = document.querySelector(".hero-mark img");

    if (reduceMotion.matches || !mark) return undefined;

    let frame = null;

    const update = () => {
      frame = null;
      const progress = Math.min(
        Math.max(window.scrollY / Math.max(window.innerHeight, 1), 0),
        1,
      );
      const compactLayout = window.innerWidth <= 1040;
      const maxOffset = compactLayout ? 10 : 24;
      const maxScaleChange = compactLayout ? 0.01 : 0.025;

      mark.style.setProperty("--scroll-offset", `${progress * maxOffset}px`);
      mark.style.setProperty(
        "--scroll-scale",
        `${1 - progress * maxScaleChange}`,
      );
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
      mark.style.removeProperty("--scroll-offset");
      mark.style.removeProperty("--scroll-scale");
    };
  }, []);
}

export function App() {
  const [connectionMode, setConnectionMode] = useState("wifi");
  const activeMode = connectionModes[connectionMode];

  useRevealMotion();
  useScrollMotion();

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
          <div className="section-inner">
            <div className="feature-overview" data-reveal>
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

            <div className="connection-switcher" data-reveal>
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
              >
                <div className="connection-panel-content" key={connectionMode}>
                  <h3>{activeMode.title}</h3>
                  <p>{activeMode.body}</p>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section
          aria-labelledby="setup-title"
          className="section setup-section"
          id="setup"
        >
          <div className="section-inner setup-inner" data-reveal>
            <header className="setup-intro">
              <p className="section-kicker">One-time setup</p>
              <h2 id="setup-title">Get Waypoint on your iPhone.</h2>
              <p className="setup-copy">
                Most of the work happens once. After that, choose a place and
                start directly from the map.
              </p>
              <p className="setup-requirements">
                iOS 26 <span aria-hidden="true">·</span> Developer Mode
                <span aria-hidden="true">·</span> LocalDevVPN
              </p>
            </header>

            <div className="setup-guide">
              <ol className="setup-steps" role="list">
                {setupSteps.map((step, index) => (
                  <li
                    className="setup-step"
                    key={step.title}
                    style={{ "--setup-delay": `${index * 65}ms` }}
                  >
                    <span className="setup-step-index" aria-hidden="true">
                      {String(index + 1).padStart(2, "0")}
                    </span>
                    <div>
                      <h3>{step.title}</h3>
                      <p>{step.body}</p>
                      {step.actions ? (
                        <div className="setup-step-links">
                          {step.actions.map((action) => (
                            <a
                              className={
                                action.primary
                                  ? "setup-step-link is-primary"
                                  : "setup-step-link"
                              }
                              href={action.href}
                              key={action.label}
                            >
                              {action.label}
                            </a>
                          ))}
                        </div>
                      ) : null}
                    </div>
                  </li>
                ))}
              </ol>

              <aside className="setup-security">
                <strong>Keep your pairing record private.</strong>
                <p>
                  It is a trusted credential for your iPhone. Never upload it,
                  paste it into an issue, or include it in logs or screenshots.
                </p>
              </aside>

              <details className="setup-details" id="pairing-help">
                <summary>Pairing file help</summary>
                <div className="setup-details-content">
                  <ul>
                    <li>
                      <strong>Using SideStore:</strong> choose Import with
                      SideStore when Waypoint asks.
                    </li>
                    <li>
                      <strong>Using Files:</strong> connect the unlocked iPhone
                      by USB, trust the computer, create an RPPairing record,
                      then save it to Files on the iPhone.
                    </li>
                  </ul>
                  <a className="setup-step-link" href={links.pairingTool}>
                    Open the pairing tool
                  </a>
                </div>
              </details>

              <details className="setup-details">
                <summary>
                  Starting without Wi-Fi <span>Experimental</span>
                </summary>
                <ol>
                  <li>Turn Wi-Fi off and confirm that 4G or 5G is working.</li>
                  <li>Choose a location and tap Start on mobile data.</li>
                  <li>
                    Follow the Airplane Mode on and off prompts exactly, keeping
                    Wi-Fi off.
                  </li>
                  <li>Wait until Waypoint confirms the spoof is active.</li>
                </ol>
              </details>

              <p className="setup-help">
                When finished, tap Stop before disconnecting LocalDevVPN. Need
                more help?{" "}
                <a href={links.fullSetup}>
                  Read the full setup and troubleshooting guide.
                </a>
              </p>
            </div>
          </div>
        </section>
      </main>

      <footer className="site-footer" data-reveal>
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
