import { useRef } from "react";
import { DownloadSimple } from "@phosphor-icons/react";
import { assets, links, proofPoints } from "../content/siteContent.js";
import { useHeroParallax } from "../hooks/useHeroParallax.js";

export function HeroSection() {
  const imageRef = useRef(null);
  useHeroParallax(imageRef);

  return (
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
          ref={imageRef}
          src={assets.heroPhone}
          alt=""
          width="760"
          height="860"
          fetchPriority="high"
        />
      </div>
    </section>
  );
}
