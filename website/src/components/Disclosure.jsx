import { CaretDown } from "@phosphor-icons/react";
import { useState } from "react";

export function Disclosure({ children, id, label, meta }) {
  const [isOpen, setIsOpen] = useState(false);
  const triggerId = `${id}-trigger`;
  const panelId = `${id}-panel`;

  return (
    <div className={`disclosure${isOpen ? " is-open" : ""}`} id={id}>
      <button
        aria-controls={panelId}
        aria-expanded={isOpen}
        className="disclosure-trigger"
        id={triggerId}
        onClick={() => setIsOpen((open) => !open)}
        type="button"
      >
        <span>{label}</span>
        <span className="summary-meta">
          {meta}
          <CaretDown
            aria-hidden="true"
            className="summary-chevron"
            size={18}
            weight="bold"
          />
        </span>
      </button>

      <div
        aria-hidden={!isOpen}
        aria-labelledby={triggerId}
        className="disclosure-panel"
        id={panelId}
        inert={isOpen ? undefined : true}
        role="region"
      >
        <div className="disclosure-panel-inner">
          <div className="details-content">{children}</div>
        </div>
      </div>
    </div>
  );
}
