---
name: timescale
description: Read and configure Timescale progress data for time-aware planning, including routines, waking-day, week, month, quarter, year, sunlight, and estimated-life context. Use when a user asks how much of a period has elapsed or remains, wants plans sized to their remaining configured day, or explicitly asks to update Timescale settings.
---

# Timescale

Use the local `timescale` command as the source of truth. Do not launch the interactive TUI from a non-interactive agent session.

## Availability

Check that `timescale` is on `PATH` before using it. If it is unavailable, explain that Timescale must be installed; do not install it unless the user asks.

Run `timescale doctor` when configuration or environment problems are suspected.

## Read progress

Use `timescale status --json` for calculations, planning, or integration. The output contains:

- `generatedAt`: timestamp for the snapshot.
- `routine`: optional active routine progress, including its name, start/end, elapsed fraction, remaining seconds, and completion state.
- `rows`: configured periods in display order.
- `elapsed`: fraction from 0 to 1, not a percentage from 0 to 100.
- `remainingSeconds` and `onePercentSeconds`: exact durations suitable for calculations.
- `start` and `end`: period boundaries.
- `detail`: labels such as quarter boundaries or current age.
- `marker`: optional fractional position, currently used for the birthday marker on the year.
- `solar`: optional sunrise and sunset timestamps plus their positions within the configured waking day.

Use `timescale status` only when human-readable output is sufficient. Describe snapshots in plain language and include the relevant timestamp or timezone when freshness matters.

Treat waking-day progress as the user's configured usable day, not a midnight-to-midnight calendar day. Use the returned boundaries instead of reconstructing periods independently.

## Help with planning

When asked to plan work, use remaining time as context rather than as a command. Distinguish elapsed calendar time from available attention, deadlines, and task estimates. Do not imply that a high percentage is failure or that all remaining time should be scheduled.

Useful tasks include:

- reporting how much of today, this week, month, quarter, or year remains;
- sizing a proposed task against the configured waking day;
- identifying approaching week, quarter, or year boundaries;
- producing a concise daily or quarterly planning summary;
- using sunrise or sunset as a planning constraint when solar data is configured;
- returning raw JSON-derived values to another local automation.

The life row is an editable statistical visualization, not a personal prediction or medical guidance. State that distinction when interpreting it beyond simply reporting the value.

## Change settings

Read-only status requests do not authorize configuration changes. Modify settings only when the user explicitly asks, using:

```sh
timescale config show
timescale config set <key> <value>
```

Supported keys and values:

- `day.start`, `day.end`: `HH:MM`.
- `routine.name`: non-empty text.
- `routine.durationMinutes`: integer from 1 to 10080.
- `routine.startedAt`: RFC 3339 timestamp or `null`.
- `week.startsOn`: `monday` or `sunday`.
- `quarter.cycle`: `calendar` or `japanFiscal`.
- `solar.enabled`: boolean.
- `solar.latitude`, `solar.longitude`: decimal number or `null`; set or clear both together.
- `life.birthDate`: `YYYY-MM-DD` or `null`.
- `life.country`: text.
- `life.expectancyYears`: number greater than 0 and at most 150.
- `visible`: comma-separated `day,week,month,quarter,year,life` values.
- `tui.theme`: `auto`, `color`, `catppuccin`, `tokyoNight`, `gruvbox`, or `monochrome`.
- `tui.motion`: `full`, `reduced`, or `off`.

After changing settings, run `timescale doctor` and then `timescale status --json` to verify the resulting configuration. On macOS these settings are shared with the native menu-bar app.

For unsupported or multi-field edits, locate the file with `timescale config path`, inspect it with `timescale config show`, and ask before editing the JSON directly.
