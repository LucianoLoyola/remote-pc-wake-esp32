# WakeDesk brand guide

Use these values everywhere (firmware web UI, the PC app, the website, images and documentation) so the whole system looks like one product.

## Name

- **WakeDesk**: one word, capital W and D. Not "Wakedesk", "Wake Desk" or "WAKEDESK".
- Tagline: *Your desktop, wherever you are.*
- One-line description: *Wake and control your Windows PC from anywhere with a tiny ESP32 and Telegram. No port forwarding, works behind CGNAT.*

The project was previously called *remote-pc-wake*. Some technical identifiers keep that name so existing installations keep working: the ESP32 network name (`remote-pc-wake.local`), the firmware folder (`firmware/remote-pc-wake/`), the agent's scheduled task and firewall rule (`Remote PC Wake Agent`) and its folder (`C:\ProgramData\RemotePcWake`). New components use the WakeDesk name.

## Colors

The brand is **dark navy with cyan and blue accents**. Every color has a light-mode and a dark-mode value; both meet WCAG AA contrast (4.5:1) for text.

| Role | Dark mode | Light mode | Use |
|---|---|---|---|
| Background | `#0B1426` | `#F4F7FB` | Page background |
| Surface | `#13203A` | `#FFFFFF` | Cards, panels |
| Border | `#22314F` | `#DCE3EE` | Borders, dividers, empty bars |
| Text | `#E6EDF7` | `#0B1426` | Headings and body text |
| Text muted | `#8FA3BF` | `#4A5B75` | Labels, hints, secondary text |
| **Primary** | `#22D3EE` | `#0E7490` | Main buttons, links, focus, highlights |
| Text on primary | `#0B1426` | `#FFFFFF` | Text on primary buttons |
| Secondary | `#3B82F6` | `#1D4ED8` | Charts, secondary accents |
| Success | `#22C55E` | `#15803D` | "PC is on", confirmations |
| Warning | `#F59E0B` | `#B45309` | "Waking up", warnings |
| Danger | `#EF4444` | `#B91C1C` | "PC is off", errors, destructive actions |

**Brand gradient:** `#22D3EE` to `#3B82F6` (cyan to blue). For logos, banners and glow effects, not for text.

In dark mode, primary buttons use **navy text on cyan**: white text on light cyan isn't readable.

### CSS tokens

```css
:root {
  --bg: #F4F7FB;  --surface: #FFFFFF;  --border: #DCE3EE;
  --text: #0B1426; --text-muted: #4A5B75;
  --primary: #0E7490; --on-primary: #FFFFFF;
  --secondary: #1D4ED8;
  --success: #15803D; --warning: #B45309; --danger: #B91C1C;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0B1426;  --surface: #13203A;  --border: #22314F;
    --text: #E6EDF7; --text-muted: #8FA3BF;
    --primary: #22D3EE; --on-primary: #0B1426;
    --secondary: #3B82F6;
    --success: #22C55E; --warning: #F59E0B; --danger: #EF4444;
  }
}
```

### For image generators

> Color palette: deep navy `#0B1426` background, cyan `#22D3EE` and electric blue `#3B82F6` accents, soft glow, no text.

## Images

- Show the ESP32 **powered by a wall charger**, never connected to the PC: it talks to the PC only over the network.
- Don't put text in generated images; add the name afterwards with an editor.
- GitHub social preview: 1280 × 640 px.
