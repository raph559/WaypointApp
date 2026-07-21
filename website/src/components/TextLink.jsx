import { ArrowUpRight } from "@phosphor-icons/react";

export function TextLink({ children, href }) {
  return (
    <a className="text-link" href={href}>
      <span>{children}</span>
      <ArrowUpRight aria-hidden="true" size={15} weight="bold" />
    </a>
  );
}
