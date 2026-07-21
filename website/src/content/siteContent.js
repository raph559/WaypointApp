import {
  Code,
  DeviceMobile,
  Lightning,
  LockSimple,
} from "@phosphor-icons/react";

export const links = {
  download:
    "https://github.com/raph559/WaypointApp/releases/latest/download/Waypoint-iOS26-unsigned.ipa",
  github: "https://github.com/raph559/WaypointApp",
  setup: "#setup",
  fullSetup: "https://github.com/raph559/WaypointApp#first-time-setup",
  sideStore: "https://docs.sidestore.io/docs/installation/install",
  altStore: "https://faq.altstore.io/altstore-classic/altserver",
  localDevVPN: "https://apps.apple.com/app/id6755608044",
  developerMode:
    "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device",
  pairingTool: "https://github.com/jkcoxson/idevice_pair",
  contributing:
    "https://github.com/raph559/WaypointApp/blob/main/CONTRIBUTING.md",
  security: "https://github.com/raph559/WaypointApp/blob/main/SECURITY.md",
  license: "https://github.com/raph559/WaypointApp/blob/main/LICENSE",
};

const assetUrl = (filename) => `${import.meta.env.BASE_URL}${filename}`;

export const assets = {
  icon: assetUrl("waypoint-icon.png"),
  heroPhone: assetUrl("waypoint-hero-phone-v3.png"),
  setupIllustration: assetUrl("waypoint-setup-illustration-v2.png"),
  journeySurface: assetUrl("waypoint-journey-surface-v2.png"),
};

export const proofPoints = [
  { label: "Open source", icon: Code },
  { label: "No jailbreak", icon: LockSimple },
  { label: "No JIT", icon: Lightning },
  { label: "iOS 26", icon: DeviceMobile },
];

export const capabilities = [
  {
    title: "Pick a place.",
    body: "Search, tap the map, or drag the pin.",
    tone: "mint",
  },
  {
    title: "Start spoofing.",
    body: "Move again without restarting the simulation.",
    tone: "coral",
  },
  {
    title: "Know when it stops.",
    body: "Optional alerts tell you when confirmation is lost.",
    tone: "blue",
  },
];

export const setupSteps = [
  {
    title: "Choose an installer.",
    body:
      "Waypoint is an unsigned IPA. Use SideStore or AltStore Classic to sign and install it.",
    tone: "mint",
    actions: [
      { label: "Install SideStore", href: links.sideStore },
      { label: "Use AltStore", href: links.altStore },
    ],
  },
  {
    title: "Prepare your iPhone.",
    body:
      "When your installer prompts you, enable Developer Mode and restart. Install LocalDevVPN and accept its VPN permission once.",
    tone: "coral",
    actions: [
      { label: "Developer Mode help", href: links.developerMode },
      { label: "Get LocalDevVPN", href: links.localDevVPN },
    ],
  },
  {
    title: "Download Waypoint.",
    body: "Get the latest IPA, then open it in SideStore or AltStore to install it.",
    tone: "blue",
    actions: [{ label: "Download IPA", href: links.download }],
  },
  {
    title: "Start and pair.",
    body:
      "Choose a location and tap Start spoofing. Waypoint follows the active connection. If asked, import directly from SideStore or select this iPhone's pairing file from Files.",
    tone: "mint",
  },
  {
    title: "Let setup finish.",
    body:
      "Keep Waypoint open while it downloads about 17 MB of support files. On Wi-Fi, just wait for Spoof Active. On mobile data, follow the two guided Airplane Mode prompts.",
    tone: "coral",
  },
];
