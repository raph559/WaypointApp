import { useEffect, useLayoutEffect } from "react";
import {
  ArrowUpRight,
  CaretDown,
  Code,
  DeviceMobile,
  DownloadSimple,
  Info,
  Lightning,
  LockSimple,
  ShieldCheck,
} from "@phosphor-icons/react";

const links = {
  download:
    "https://github.com/raph559/WaypointApp/releases/latest/download/Waypoint-iOS26-unsigned.ipa",
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
const heroPhoneUrl = `${import.meta.env.BASE_URL}waypoint-hero-phone.webp`;
const setupIllustrationUrl = `${import.meta.env.BASE_URL}waypoint-setup-illustration.webp`;
const journeySurfaceUrl = `${import.meta.env.BASE_URL}waypoint-journey-surface.webp`;

const proofPoints = [
  { label: "Open source", icon: Code },
  { label: "No jailbreak", icon: LockSimple },
  { label: "No JIT", icon: Lightning },
  { label: "iOS 26", icon: DeviceMobile },
];

const capabilities = [
  {
    title: "Pick a place.",
    body: "Search, tap the map, or drag the pin.",
    tone: "mint",
  },
  {
    title: "Start spoofing.",
    body: "Move again without restarting the simulation.",
    tone: "coral",
  },
  {
    title: "Know when it stops.",
    body: "Optional alerts tell you when confirmation is lost.",
    tone: "blue",
  },
];

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
    actions: [{ label: "Download IPA", href: links.download }],
  },
  {
    title: "Start and pair.",
    body:
      "Choose a location and tap Start spoofing. Waypoint follows the active connection. If asked, import directly from SideStore or select this iPhone's pairing file from Files.",
  },
  {
    title: "Let setup finish.",
    body:
      "Keep Waypoint open while it downloads about 17 MB of support files. On Wi-Fi, just wait for Spoof Active. On mobile data, follow the two guided Airplane Mode prompts.",
  },
];

function useRevealMotion() {
  useLayoutEffect(() => {
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

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
  }, []);
}

function useScrollMotion() {
  useEffect(() => {
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const artwork = document.querySelector(".hero-artwork img");

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
  }, []);
}

function TextLink({ children, href }) {
  return (
    <a className="text-link" href={href}>
      <span>{children}</span>
      <ArrowUpRight aria-hidden="true" size={15} weight="bold" />
    </a>
  );
}

export function App() {
  useRevealMotion();
  useScrollMotion();

  return (
    <div className="site-shell" id="top">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>

      <header className="site-header">
        <a className="brand" href="#top" aria-label="Waypoint home">
          <img src={iconUrl} alt="" width="42" height="42" />
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
                <DownloadSimple aria-hidden="true" size={19} weight="bold" />
                Download IPA
              </a>
              <a className="button button-secondary" href={links.setup}>
                Setup guide
              </a>
            </div>

            <div className="proof-strip" aria-label="Waypoint requirements">
              {proofPoints.map(({ label, icon: Icon }) => (
                <span key={label}>
                  <Icon aria-hidden="true" size={19} weight="regular" />
                  {label}
                </span>
              ))}
            </div>
          </div>

          <div className="hero-artwork" aria-hidden="true">
            <img
              src={heroPhoneUrl}
              alt=""
              width="760"
              height="860"
              fetchPriority="high"
            />
          </div>
        </section>

        <section className="journey-section" id="features">
          <div className="journey-heading" data-reveal>
            <p className="section-kicker">How it works</p>
            <h2>
              Three moves,
              <br />
              one map.
            </h2>
            <p>
              Pick a destination once, then adjust your simulated location as
              often as you need.
            </p>
          </div>

          <div className="journey-track">
            <img
              className="journey-route-art"
              data-reveal
              src={journeySurfaceUrl}
              alt=""
              width="1440"
              height="430"
              loading="lazy"
            />
            <ol className="journey-list" role="list">
              {capabilities.map((capability, index) => (
                <li
                  className="journey-step"
                  data-reveal
                  data-tone={capability.tone}
                  key={capability.title}
                  style={{ "--reveal-delay": `${index * 90}ms` }}
                >
                  <span className="journey-number" aria-hidden="true">
                    {index + 1}
                  </span>
                  <div>
                    <h3>{capability.title}</h3>
                    <p>{capability.body}</p>
                  </div>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section
          aria-labelledby="setup-title"
          className="setup-section"
          id="setup"
        >
          <div className="setup-aside" data-reveal>
            <p className="section-kicker">One-time setup</p>
            <h2 id="setup-title">
              <span>Setup once.</span>
              <br />
              <span>Then just go.</span>
            </h2>
            <p>
              The first connection takes a few steps. Waypoint keeps the path
              clear and puts the right help exactly where you need it.
            </p>

            <img
              className="setup-illustration"
              src={setupIllustrationUrl}
              alt=""
              width="520"
              height="480"
              loading="lazy"
            />

            <aside className="setup-note setup-note-security">
              <ShieldCheck aria-hidden="true" size={24} weight="regular" />
              <div>
                <strong>Keep your pairing record private.</strong>
                <p>
                  It is a trusted credential for your iPhone. Never upload it,
                  paste it into an issue, or include it in logs or screenshots.
                </p>
              </div>
            </aside>
          </div>

          <div className="setup-guide">
            <ol className="setup-steps" role="list">
              {setupSteps.map((step, index) => (
                <li
                  className="setup-step"
                  data-reveal
                  data-tone={capabilities[index % capabilities.length].tone}
                  key={step.title}
                  style={{ "--reveal-delay": `${index * 70}ms` }}
                >
                  <span className="setup-step-index" aria-hidden="true">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div className="setup-step-copy">
                    <h3>{step.title}</h3>
                    <p>{step.body}</p>
                    {step.actions ? (
                      <div className="setup-step-actions">
                        {step.actions.map((action) => (
                          <TextLink href={action.href} key={action.label}>
                            {action.label}
                          </TextLink>
                        ))}
                      </div>
                    ) : null}
                  </div>
                </li>
              ))}
            </ol>

            <div className="setup-disclosures" data-reveal>
              <details id="pairing-help">
                <summary>
                  <span>Pairing file help</span>
                  <span className="summary-meta">
                    <span className="summary-label">Private</span>
                    <CaretDown
                      aria-hidden="true"
                      className="summary-chevron"
                      size={18}
                      weight="bold"
                    />
                  </span>
                </summary>
                <div className="details-content">
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
                  <TextLink href={links.pairingTool}>
                    Open the pairing tool
                  </TextLink>
                </div>
              </details>

              <details id="mobile-data-start">
                <summary>
                  <span>Starting on mobile data</span>
                  <CaretDown
                    aria-hidden="true"
                    className="summary-chevron"
                    size={18}
                    weight="bold"
                  />
                </summary>
                <div className="details-content">
                  <ol>
                    <li>Turn Wi-Fi off and confirm that 4G or 5G is working.</li>
                    <li>Choose a location and tap Start on mobile data.</li>
                    <li>
                      Follow the Airplane Mode on and off prompts exactly,
                      keeping Wi-Fi off.
                    </li>
                    <li>Wait until Waypoint confirms the spoof is active.</li>
                  </ol>
                </div>
              </details>
            </div>

            <p className="setup-help" data-reveal>
              <Info aria-hidden="true" size={19} weight="regular" />
              <span>
                Tap Stop before disconnecting LocalDevVPN. Need more help?{" "}
                <a href={links.fullSetup}>Open the complete troubleshooting guide.</a>
              </span>
            </p>
          </div>
        </section>
      </main>

      <footer className="site-footer" data-reveal>
        <div className="footer-brand">
          <div className="brand-line">
            <img src={iconUrl} alt="" width="42" height="42" />
            <span>Waypoint</span>
          </div>
          <p>Open-source iOS location simulation, directly from your iPhone.</p>
          <a href={links.github}>github.com/raph559/WaypointApp</a>
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
