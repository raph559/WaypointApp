# Waypoint website design QA

## Evidence

- Source visual truth: `/workspace/scratch/39bbb15352a6/generated_images/exec-dc0ecc7e-5244-4889-ba85-82cb62f379fe.png`
- Focused journey-section source: `/workspace/scratch/39bbb15352a6/generated_images/exec-f521bcff-8e5f-4b19-a83c-907d4381bda3.png`
- Focused setup-section source: `/workspace/scratch/39bbb15352a6/generated_images/exec-d09bb700-f578-4dfc-9145-ab10f207b729.png`
- User-reported journey capture: `/workspace/scratch/39bbb15352a6/upload/image(42).png`
- User-reported hero capture: `/workspace/scratch/39bbb15352a6/upload/image(43).png`
- User-reported setup-number capture: `/workspace/scratch/39bbb15352a6/upload/image(44).png`
- User-reported hero-spacing capture: `/workspace/scratch/39bbb15352a6/upload/image(45).png`
- Rendered implementation: `https://raph559.github.io/WaypointApp/#setup` in the cloud browser
- Implementation screenshot evidence: inline browser-rendered captures from the deployed GitHub Pages site; the browser runtime did not expose a persistent filesystem path
- Viewport: 1363 × 936, desktop dark theme
- States reviewed: hero at rest, map journey after scroll reveal, setup section, both setup disclosures opened
- Full-view evidence: the complete source mockup was reviewed alongside browser captures covering the full implemented page in three contiguous regions
- Focused comparison evidence: source and implementation were emitted together for the hero, revised horizontal map journey, revised setup timeline, and final hero-spacing regions

## Findings

- No actionable P0, P1, or P2 differences remain.
- The connection-mode comparison in the source visual was intentionally removed after the user rejected that section. The implementation now explains mobile-data handoff only where it affects setup.
- The source's old cautionary cellular treatment was intentionally replaced with supported, connection-aware language at the user's direction.

## Required fidelity surfaces

- Fonts and typography: system display and text faces preserve the source hierarchy, compact weight contrast, tight display tracking, and two-line hero/setup wraps.
- Spacing and layout rhythm: the asymmetric hero, compact journey header, shared horizontal journey surface, rounded setup section, 2 px borders, and compact footer match the approved direction without the removed mode block.
- Colors and tokens: charcoal, slate, warm off-white, mint, coral, and dusty blue stay balanced; generated-image backgrounds were normalized to their parent surfaces so no hard rectangular matte remains.
- Image quality: the generated phone uses a dedicated 1181 × 1332 high-detail PNG; the route and setup artwork use lossless 1440 × 430 and 1040 × 960 PNG sources. All three loaded at their full natural dimensions. No placeholder, CSS-drawn, or handcrafted SVG artwork is used.
- Copy and content: primary actions, installer links, pairing privacy, mobile-data steps, disconnect guidance, and supported platform language are accurate and concise. No deprecated cellular caveat label remains.
- Icons and affordances: Phosphor icons are consistent, buttons and links have clear hover/focus behavior, and disclosure chevrons reflect open state.
- Interactions: Setup navigation, both native disclosures, installer links, and stable latest-IPA links were exercised. Both disclosures opened successfully.
- Responsiveness and accessibility: semantic landmarks, skip link, heading order, focus rings, 44 px tap targets, reduced-motion handling, and no horizontal overflow were verified. The 390 px breakpoint was inspected in CSS; this browser session did not expose viewport emulation for a separate mobile capture.
- Console and loading: the browser pass reported no console errors; every visible image loaded at its expected natural dimensions.

## Comparison history

1. Earlier P2: the setup title wrapped too aggressively, mid-width setup columns could overflow, narrow headings could clip, and disclosure focus rings were cut off.
   - Fixes: locked the intended two-line desktop title, raised the single-column breakpoint, allowed narrow-screen wrapping, and moved focus outlines inside the rounded disclosure surface.
   - Post-fix evidence: final setup capture shows the two-line title, aligned five-step guide, intact borders, and unclipped disclosure container.
2. Earlier P2: generated hero and setup assets exposed dark rectangular mattes against their parent surfaces.
   - Fixes: normalized the raster backgrounds to the page and setup surface colors, then shipped optimized WebP assets.
   - Post-fix evidence: final hero and setup captures show continuous backgrounds around both illustrations.
3. Earlier P2: the feature list lacked the distinctive route motif from the approved direction.
   - Fix: added a generated raster route and aligned the numbered steps along it.
   - Post-fix evidence: the route establishes the mint/coral/blue sequence without the removed connection-mode cards.
4. User-directed content revision: removed the entire Wi-Fi/mobile comparison block and elevated mobile data to normal supported setup copy.
   - Post-fix evidence: DOM and visible-copy checks found zero deprecated caveat labels and zero connection-mode cards.
5. Latest P2: the vertical journey layout left a large empty center and lower half, making the steps feel detached from the hero.
   - Fixes: created a focused visual revision, replaced the tall floating route with one wide rounded map surface, moved the three steps into a balanced left-to-right sequence, and reduced the gap before setup. Below 760 px, the same content becomes a compact stacked list inside one rounded surface.
   - Post-fix evidence: the focused source and browser render were compared together at 1365 × 936. The final render preserves the heading hierarchy and route rhythm while removing the dead space; the panel has no horizontal overflow and its 1440 × 430 raster loaded at full natural size.
6. Latest P2: the right side of the setup section read as a generic settings table and visually conflicted with the editorial title and illustration on the left.
   - Fixes: replaced circular badges, full-width separators, and the detached utility-link column with one quiet vertical rail, tabular `01–05` labels, compact editorial step blocks, and help links placed directly beneath their relevant copy.
   - Post-fix evidence: the focused source and deployed browser render were emitted together at 1363 × 936. The live section has five padded labels, no step borders, a 2 px timeline rail, 44 px action targets, no horizontal overflow, and no page-origin console errors.
7. Latest P2: the live journey markers were visibly smaller than the approved mockup, the route and phone artwork were softened by aggressive WebP compression, and the wide setup title approached the column divider.
   - Fixes: increased desktop markers from 54 × 54 to 64 × 64, re-exported the route and setup artwork from their lossless sources, replaced the cropped hero derivative with a dedicated high-detail render, and slightly reduced the wide-screen setup heading scale.
   - Post-fix evidence: user captures and deployed browser captures were emitted together at 1363 × 936. The live markers measure 64 × 64 with 22.4 px numerals; the route, hero, and setup assets report natural dimensions of 1440 × 430, 1181 × 1332, and 1040 × 960; the setup title clears the divider by 57 px; horizontal overflow and page-origin console errors are both zero.
8. Latest P2: the `01–05` setup numbers remained too small to anchor the timeline and read like metadata beside the step titles.
   - Fixes: increased the desktop numerals to a fluid 39.2–46.4 px range, widened their grid column, and realigned the timeline rail and colored nodes around the larger type. Dedicated 32.8 px and 29.6 px sizes preserve the hierarchy at the mobile breakpoints.
   - Post-fix evidence: the user capture and deployed setup render were emitted together at 1363 × 936. Each live desktop number measures 84 × 42 with a computed 42.93 px font size; the rail and nodes align with the enlarged numerals, title clearance remains 57 px, horizontal overflow is zero, and the page reports no console warnings or errors.
9. User-directed maintenance pass: the 1,268-line stylesheet and 456-line page component made unrelated sections difficult to own and review.
   - Fixes: split the stylesheet into 12 ordered source files with a 273-line maximum, decomposed the page into section and layout components with a 30-line `App.jsx`, scoped motion hooks to React refs, made setup tones explicit, and added ESLint, Stylelint, source-size limits, and a CI `npm run check` gate.
   - Post-fix evidence: the production CSS bundle retained the exact same `index-CtOdwIcK.css` hash. Before/after browser measurements for the page, header, hero, journey, setup, footer, image dimensions, typography, and overflow were byte-for-byte identical at 1363 × 936. Navigation, the pairing disclosure, reveal state, and parallax setup still work; no page-origin console warnings or errors were reported. A clean `npm ci` and `npm run check` both pass locally.
10. Latest P2: the desktop hero still inherited a 108 px copy offset, leaving roughly 200 px of dead space between the navigation and the eyebrow in the user capture.
   - Fixes: removed the copy offset entirely, aligned copy and artwork at the top of the hero grid, and set deliberate top padding of 28 px on desktop and narrow mobile layouts, with 36 px at the stacked tablet breakpoint.
   - Post-fix evidence: the user capture and corrected browser render were emitted together in one comparison pass. At 1363 × 936, the live header ends at y=104 and the eyebrow and artwork both begin at y=132, producing a measured 28 px content gap instead of the former structural offset. Horizontal overflow is zero, the Setup navigation still reaches `#setup`, and no page-origin console warnings or errors were reported. The source capture is a 1579 × 347 crop, so comparison focused on the shared top-of-page region rather than absolute viewport scaling.

## Residual P3 polish

- Capture a physical narrow-phone screenshot after deployment to supplement the CSS breakpoint inspection.

## Implementation checklist

- [x] Match the approved visual direction
- [x] Remove the rejected connection-mode comparison
- [x] Treat mobile data as supported throughout visible copy
- [x] Keep setup concise and directly usable on the website
- [x] Replace the empty vertical journey with the approved compact horizontal composition
- [x] Align the setup instructions with the editorial left-hand composition
- [x] Verify reveal motion, reduced motion, disclosures, links, imagery, and overflow
- [x] Keep authored CSS and JSX within enforced maintainability limits
- [x] Run lint, source-size checks, and the production build in CI
- [x] Build the production website bundle

final result: passed
