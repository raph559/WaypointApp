const links = {
  download: "https://github.com/raph559/WaypointApp/releases/latest",
  github: "https://github.com/raph559/WaypointApp",
  setup: "https://github.com/raph559/WaypointApp#first-time-setup",
  privacy: "https://github.com/raph559/WaypointApp#privacy-and-data-flow",
  limitations:
    "https://github.com/raph559/WaypointApp#compatibility-and-limitations",
  localDevVPN: "https://apps.apple.com/app/id6755608044",
  developerSupport: "https://github.com/doronz88/DeveloperDiskImage",
  issues: "https://github.com/raph559/WaypointApp/issues",
  contributing:
    "https://github.com/raph559/WaypointApp/blob/main/CONTRIBUTING.md",
  security: "https://github.com/raph559/WaypointApp/blob/main/SECURITY.md",
  license: "https://github.com/raph559/WaypointApp/blob/main/LICENSE",
};

const iconUrl = `${import.meta.env.BASE_URL}waypoint-icon.png`;
const markUrl = `${import.meta.env.BASE_URL}waypoint-mark.png`;

const steps = [
  {
    number: "01",
    title: "Find it",
    body: "Search with MapKit, tap anywhere on the map, or drag the pin to precise coordinates.",
  },
  {
    number: "02",
    title: "Start it",
    body: "Waypoint checks pairing, developer support, and LocalDevVPN within the Start flow.",
  },
  {
    number: "03",
    title: "Move anytime",
    body: "Update an active simulation instantly, then stop it cleanly when you are finished.",
  },
];

const features = [
  {
    title: "Map-first controls",
    body: "Place autocomplete, tap selection, a draggable pin, and a precise coordinate readout without leaving the map.",
  },
  {
    title: "Connection-aware start",
    body: "A direct Wi-Fi flow and a guided cellular-only handoff when Wi-Fi is unavailable.",
  },
  {
    title: "Clear state feedback",
    body: "Waypoint shows clear start, move, stop, active, and connection-loss feedback, with haptics for each change.",
  },
  {
    title: "Local disconnect alerts",
    body: "Optional notifications warn when Waypoint can no longer confirm the simulation heartbeat—even offline.",
  },
];

const requirements = [
  "An iPhone running iOS 26 with Developer Mode enabled",
  "The unsigned IPA signed with your preferred compatible method",
  "LocalDevVPN installed with its one-time VPN permission accepted",
  "A pairing record created specifically for this iPhone",
  "Internet access for the initial developer-support download and MapKit search",
];

const limits = [
  "iOS marks the location as software-simulated, and apps can detect or reject it.",
  "Apps may compare location with IP address, time zone, Wi-Fi, cellular, or motion data.",
  "A disconnect alert means confirmation was lost; it cannot prove the exact moment real location returned.",
  "Wi-Fi on iOS 26 is the primary supported path. Cellular-only start remains experimental and device-dependent.",
  "Tap Stop before disconnecting LocalDevVPN. If Stop cannot be confirmed, disconnect LocalDevVPN or restart the iPhone, then verify the reported location.",
];

export function App() {
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
              Choose a place on the map and control Apple&apos;s developer
              location simulation directly from your iPhone.
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

        <section className="mantra" aria-label="Waypoint summary">
          <p>Search. Place. Simulate.</p>
          <a href="#workflow" aria-label="Continue to how Waypoint works">
            Explore the app
          </a>
        </section>

        <section className="section workflow-section" id="workflow">
          <div className="section-inner">
            <header className="section-heading">
              <p className="section-kicker">The workflow</p>
              <h2>Pick a place. Start. Move anytime.</h2>
            </header>

            <div className="step-grid">
              {steps.map((step) => (
                <article className="step" key={step.number}>
                  <p className="step-number">{step.number}</p>
                  <h3>{step.title}</h3>
                  <p>{step.body}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section feature-section" id="features">
          <div className="section-inner feature-layout">
            <header className="section-heading feature-heading">
              <p className="section-kicker">What is built in</p>
              <h2>Everything around the pin stays out of your way.</h2>
              <p className="section-intro">
                Waypoint keeps the map central and makes the device connection
                understandable—even when the underlying setup is technical.
              </p>
            </header>

            <div className="feature-list">
              {features.map((feature) => (
                <article className="feature-item" key={feature.title}>
                  <h3>{feature.title}</h3>
                  <p>{feature.body}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section section-light" id="setup">
          <div className="section-inner setup-layout">
            <header className="section-heading setup-heading">
              <p className="section-kicker">First-time setup</p>
              <h2>Set up once, then start from the map.</h2>
              <p className="section-intro">
                Waypoint controls an Apple developer service, so setup is more
                involved than a typical App Store app. The guide keeps each
                requirement in one place.
              </p>
              <a className="text-link" href={links.setup}>
                Read the complete setup guide
              </a>
            </header>

            <div className="requirements-column">
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
                SideStore is an installation option, not a runtime dependency.
                <a href={links.localDevVPN}> LocalDevVPN</a> is required by the
                current connection architecture.
              </p>
            </div>
          </div>
        </section>

        <section className="section connection-section">
          <div className="section-inner">
            <header className="section-heading connection-heading">
              <p className="section-kicker">Connection modes</p>
              <h2>Start where you are connected.</h2>
            </header>

            <div className="mode-grid">
              <article className="mode">
                <div className="mode-meta">
                  <p>Wi-Fi</p>
                  <span className="mode-status mode-status-recommended">
                    Recommended
                  </span>
                </div>
                <h3>Choose a location and tap Start spoofing.</h3>
                <p>
                  Waypoint prepares the device and opens the simulation. Airplane
                  Mode is not required.
                </p>
              </article>

              <article className="mode">
                <div className="mode-meta">
                  <p>Mobile data</p>
                  <span className="mode-status">Experimental</span>
                </div>
                <h3>Keep Wi-Fi off and follow the guided handoff.</h3>
                <p>
                  Turn Wi-Fi off, confirm mobile data works, then follow the two
                  Airplane Mode prompts. Waypoint verifies that the retained
                  session still responds after 4G or 5G returns.
                </p>
              </article>
            </div>

            <p className="connection-note">
              Cellular reliability depends on the device and current iOS network
              state. If Waypoint is terminated, LocalDevVPN restarts, the iPhone
              reboots, or iOS closes the retained session, run the guided start
              again.
            </p>
          </div>
        </section>

        <section className="section trust-section" id="privacy">
          <div className="section-inner trust-layout">
            <header className="section-heading trust-heading">
              <p className="section-kicker">Privacy by architecture</p>
              <h2>Waypoint does not send your pairing record to its own server.</h2>
            </header>

            <div className="trust-copy">
              <p className="lead-copy">
                Waypoint has no account system, analytics, or Waypoint-operated
                server. After import, the pairing record is stored in Application
                Support with iOS file protection, mode 0600, and backup exclusion.
                Treat it like a secret and never share it.
              </p>
              <p>
                Apple MapKit supplies maps and search. Developer-support files are
                normally downloaded once from{` `}
                <a href={links.developerSupport}>DeveloperDiskImage</a>, cached
                on-device, and may need to be mounted again after an iPhone
                reboot. LocalDevVPN exposes the developer service through an
                on-device VPN.
              </p>
              <p>
                Importing from Files is recommended. Optional SideStore import
                passes the record through a custom callback URL that may appear in
                URL or debug logs.
              </p>
              <a className="text-link text-link-dark" href={links.privacy}>
                Read the privacy and data-flow details
              </a>
            </div>

            <ol
              className="architecture"
              aria-label="Waypoint architecture"
              role="list"
            >
              <li>Waypoint map</li>
              <li>idevice</li>
              <li>LocalDevVPN</li>
              <li>Apple DVT LocationSimulation</li>
              <li>Core Location apps</li>
            </ol>
          </div>
        </section>

        <section className="section limits-section" id="limitations">
          <div className="section-inner limits-layout">
            <header className="section-heading limits-heading">
              <p className="section-kicker">Be clear about simulation</p>
              <h2>Know what Waypoint can—and cannot—change.</h2>
              <a className="text-link" href={links.limitations}>
                Read compatibility details
              </a>
            </header>

            <ul className="limit-list" role="list">
              {limits.map((limit) => (
                <li key={limit}>{limit}</li>
              ))}
            </ul>
          </div>
        </section>

        <section className="section closing-section">
          <div className="section-inner closing-inner">
            <p className="section-kicker">Open source</p>
            <h2>Inspect it. Build it. Improve it.</h2>
            <p>
              Waypoint is open source under the GNU AGPL v3. Compatibility
              results, reproducible bug reports, and focused pull requests are
              welcome.
            </p>
            <div className="hero-actions closing-actions">
              <a className="button button-primary" href={links.github}>
                View source
              </a>
              <a className="button button-secondary" href={links.issues}>
                Report an issue
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
