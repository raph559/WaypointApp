import { links } from "../content/siteContent.js";
import { Brand } from "./Brand.jsx";

export function SiteHeader() {
  return (
    <header className="site-header">
      <Brand />

      <nav aria-label="Primary navigation">
        <a href="#features">Features</a>
        <a href="#setup">Setup</a>
        <a href={links.github}>GitHub</a>
      </nav>
    </header>
  );
}
