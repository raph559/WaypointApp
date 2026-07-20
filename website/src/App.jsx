const links = {
  download: "https://github.com/raph559/WaypointApp/releases/latest",
  github: "https://github.com/raph559/WaypointApp",
  setup: "https://github.com/raph559/WaypointApp#first-time-setup",
  license: "https://github.com/raph559/WaypointApp/blob/main/LICENSE",
};

const iconUrl = `${import.meta.env.BASE_URL}waypoint-icon.png`;
const markUrl = `${import.meta.env.BASE_URL}waypoint-mark.png`;

export function App() {
  return (
    <div className="site-shell">
      <header className="site-header">
        <a className="brand" href="./" aria-label="Waypoint home">
          <img src={iconUrl} alt="" width="48" height="48" />
          <span>Waypoint</span>
        </a>

        <nav aria-label="Primary navigation">
          <a href={links.setup}>Setup</a>
          <a href={links.github}>GitHub</a>
        </nav>
      </header>

      <main className="hero">
        <section className="hero-copy" aria-labelledby="hero-title">
          <p className="eyebrow">
            <span className="status-dot" aria-hidden="true" />
            Open source <span aria-hidden="true">·</span> iOS 26
          </p>

          <h1 id="hero-title">
            Your iPhone.
            <br />
            Any place.
          </h1>

          <p className="hero-description">
            Search for a location, move the pin, and start the simulation.
          </p>

          <div className="hero-actions">
            <a className="button button-primary" href={links.download}>
              Download IPA
            </a>
            <a className="button button-secondary" href={links.github}>
              View on GitHub
            </a>
          </div>

          <p className="trust-line">
            No jailbreak <span aria-hidden="true">·</span> Runs on-device
          </p>
        </section>

        <div className="hero-mark" aria-hidden="true">
          <img src={markUrl} alt="" width="420" height="460" />
        </div>
      </main>

      <section className="mantra" aria-label="How Waypoint works">
        <p>Search. Place. Simulate.</p>
      </section>

      <footer className="site-footer">
        <a href={links.license}>MIT License</a>
      </footer>
    </div>
  );
}
