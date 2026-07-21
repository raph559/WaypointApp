import { assets, capabilities } from "../content/siteContent.js";

export function JourneySection() {
  return (
    <section className="journey-section" id="features">
      <div className="journey-heading" data-reveal>
        <p className="section-kicker">How it works</p>
        <h2>
          Three moves,
          <br />
          one map.
        </h2>
        <p>
          Pick a destination once, then adjust your simulated location as often
          as you need.
        </p>
      </div>

      <div className="journey-track">
        <img
          className="journey-route-art"
          data-reveal
          src={assets.journeySurface}
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
  );
}
