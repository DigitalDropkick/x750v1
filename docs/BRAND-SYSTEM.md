# Brand System

## Purpose

Version 1.4 translates the public Digital Dropkick website into an operational appliance interface. It borrows the brand's identity and visual grammar while preserving the console's density, readability, local-only operation, and tiny idle footprint. It is not a copy of the website runtime.

## Source of truth

The design was checked against the public `https://digital-dropkick.com/` homepage and the workstation source at `/home/astro/Sites/digital-dropkick-site`. The website repository was read only. Its unrelated working changes were not edited, built, staged, committed, or deployed.

The stable visual vocabulary used here is:

- near-black `#020202` / `#050505` surfaces;
- paper white `#f6f4ef`, white, silver, and restrained gray text;
- website green `#4d7c0f` for brand selection and bounded primary actions;
- a brighter derived green only for focus visibility and small live accents;
- heavy uppercase display titles, small uppercase navigation, and monospaced appliance metadata;
- thin rules, technical grids, hard-edged controls, translucent panels, and image fades into black.

Operational status colors remain semantically distinct from the brand accent: green for ready, amber for hardware/configuration attention, blue for informational/running state, and red for unavailable/failed state.

## Local assets

All runtime assets are derived once on the workstation and stored below `files/www/luci-static/resources/ddk/brand/`. The router does no image processing.

| Runtime asset | Website source | Use |
| --- | --- | --- |
| `dropkick-logo.png` | `public/images/dropkick-guy.png` | Persistent navigation and header logo |
| `overview.webp` | `public/images/ai-security-agents/aisecurityhero.webp` | Field-hardware overview |
| `tools.webp` | `public/images/network-repair/network-section-6.jpg` | Tool/workbench context |
| `packages.webp` | `public/images/originals/code.jpg` | Package inventory context |
| `jobs.webp` | `public/images/originals/sudo.jpg` | Bounded job/output context |
| `settings.webp` | `public/images/originals/lock2-v2.jpg` | Locked safety-posture context |

Scenes are 960 by 320 monochrome WebP files. The exact logo is a 160 by 160 optimized PNG. The deployed set is 142,382 bytes. The local validator enforces six exact files, a 44 KiB limit per scene, a 10 KiB logo limit, and a 170 KiB combined limit. On a normal page load the browser requests only one scene plus the shared logo: between 13,796 and 45,418 bytes before normal HTTP overhead.

## Runtime boundaries

- No remote image, stylesheet, script, font, analytics, tracker, iframe, or CDN request.
- No copied website JavaScript, Astro runtime, video, or animation.
- No additional server, route, listener, daemon, cache, or persistent log.
- Brand asset selection is a fixed table keyed by the already-allowlisted page name.
- CSS remains below the `.ddk-*` namespace and does not style the GL.iNet or normal LuCI interfaces.
- Images are decorative context; live values and control labels never depend on them.

## Responsive behavior

Desktop layouts keep the photograph on the right side of the header with a strong horizontal fade. At 680 pixels and below, the photograph becomes a low-opacity full-width layer under the text with stronger horizontal and vertical fades. The instrument title, logo, version, and live data remain readable without the image, and reduced-motion preferences disable the console's existing transitions.

## Live acceptance

The 2026-08-09 deployment passed the 24-check production suite with no warnings. Authenticated Chrome validation loaded all five page scenes and both logo placements, confirmed 44-pixel mobile touch targets and visible keyboard focus, and found no external request, runtime error, or horizontal document overflow at 320 pixels, 390 pixels, or desktop width. Manual screenshot inspection confirmed that images remain subordinate to live data on phone and desktop layouts.
