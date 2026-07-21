import { assets } from "../content/siteContent.js";

export function Brand({ className = "brand", href = "#top" }) {
  return (
    <a className={className} href={href} aria-label="Waypoint home">
      <img
        src={assets.icon}
        alt=""
        width="42"
        height="42"
      />
      <span>Waypoint</span>
    </a>
  );
}
