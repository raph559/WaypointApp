import { Info, ShieldCheck } from "@phosphor-icons/react";
import { Disclosure } from "../components/Disclosure.jsx";
import { TextLink } from "../components/TextLink.jsx";
import { assets, links, setupSteps } from "../content/siteContent.js";

export function SetupSection() {
  return (
    <section aria-labelledby="setup-title" className="setup-section" id="setup">
      <div className="setup-aside" data-reveal>
        <p className="section-kicker">One-time setup</p>
        <h2 id="setup-title">
          <span>Setup once.</span>
          <br />
          <span>Then just go.</span>
        </h2>
        <p>
          The first connection takes a few steps. Waypoint keeps the path clear
          and puts the right help exactly where you need it.
        </p>

        <img
          className="setup-illustration"
          src={assets.setupIllustration}
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
              data-tone={step.tone}
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
          <Disclosure
            id="pairing-help"
            label="Pairing file help"
            meta={<span className="summary-label">Private</span>}
          >
            <ul>
              <li>
                <strong>Using SideStore:</strong> choose Import with SideStore
                when Waypoint asks.
              </li>
              <li>
                <strong>Using Files:</strong> connect the unlocked iPhone by USB,
                trust the computer, create an RPPairing record, then save it to
                Files on the iPhone.
              </li>
            </ul>
            <TextLink href={links.pairingTool}>Open the pairing tool</TextLink>
          </Disclosure>

          <Disclosure id="mobile-data-start" label="Starting on mobile data">
            <ol>
              <li>Turn Wi-Fi off and confirm that 4G or 5G is working.</li>
              <li>Choose a location and tap Start on mobile data.</li>
              <li>
                Follow the Airplane Mode on and off prompts exactly, keeping
                Wi-Fi off.
              </li>
              <li>Wait until Waypoint confirms the spoof is active.</li>
            </ol>
          </Disclosure>
        </div>

        <p className="setup-help" data-reveal>
          <Info aria-hidden="true" size={19} weight="regular" />
          <span>
            Tap Stop before disconnecting LocalDevVPN. Need more help?{" "}
            <a href={links.fullSetup}>
              Open the complete troubleshooting guide.
            </a>
          </span>
        </p>
      </div>
    </section>
  );
}
