import { assets, links } from "../content/siteContent.js";

export function SiteFooter() {
  return (
    <footer className="site-footer" data-reveal>
      <div className="footer-brand">
        <div className="brand-line">
          <img src={assets.icon} alt="" width="42" height="42" />
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
  );
}
