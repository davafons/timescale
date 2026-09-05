use std::env;
use std::error::Error;
use std::io::{self, stdout};
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration as StdDuration, Instant};

use chrono::{DateTime, Duration, Local};
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, Padding, Paragraph};
use serde_json::json;
use tachyonfx::{CellFilter, Duration as FxDuration, Effect, Interpolation, fx};
use timescale_core::{
    ConfigStore, Period, QuarterCycle, Settings, Snapshot, TuiMotion, TuiTheme, WeekStart, snapshot,
};

mod settings_ui;

use settings_ui::{MenuAction, SettingsMenu};

const HOURGLASS_FRAMES: [&str; 4] = ["⣹⣏", "⠹⣆", "⡷⢾", "⣰⠏"];

struct ParsedCli {
    config: Option<PathBuf>,
    command: Option<Commands>,
}

enum Commands {
    Status { json: bool, waybar: bool },
    Config { command: ConfigCommand },
    Doctor,
    Help,
    Version,
}

enum ConfigCommand {
    Path,
    Show,
    Edit,
    Set { key: String, value: String },
}

struct TuiEffects {
    accent_wave: Option<Effect>,
    sunlight_breathe: Option<Effect>,
    accent: Color,
    solar: Color,
    motion: TuiMotion,
}

impl TuiEffects {
    fn new(settings: &Settings) -> Self {
        let palette = theme_palette(settings);
        let (accent_wave, sunlight_breathe) = match settings.tui.motion {
            TuiMotion::Full => (
                Some(fx::repeating(fx::ping_pong(
                    fx::lighten_fg(0.18, (4_200, Interpolation::SineInOut))
                        .with_filter(CellFilter::FgColor(palette.accent)),
                ))),
                Some(fx::repeating(fx::ping_pong(
                    fx::lighten_fg(0.08, (5_200, Interpolation::SineInOut))
                        .with_filter(CellFilter::FgColor(palette.solar)),
                ))),
            ),
            TuiMotion::Reduced => (
                Some(fx::repeating(fx::ping_pong(
                    fx::lighten_fg(0.10, (6_000, Interpolation::SineInOut))
                        .with_filter(CellFilter::FgColor(palette.accent)),
                ))),
                None,
            ),
            TuiMotion::Off => (None, None),
        };
        Self {
            accent_wave,
            sunlight_breathe,
            accent: palette.accent,
            solar: palette.solar,
            motion: settings.tui.motion.clone(),
        }
    }

    fn refresh_if_needed(&mut self, settings: &Settings) {
        let palette = theme_palette(settings);
        if self.accent != palette.accent
            || self.solar != palette.solar
            || self.motion != settings.tui.motion
        {
            *self = Self::new(settings);
        }
    }

    fn render(&mut self, frame: &mut ratatui::Frame<'_>, elapsed: StdDuration) {
        let elapsed = FxDuration::from_millis(elapsed.as_millis().min(u32::MAX as u128) as u32);
        let area = frame.area();
        let buffer = frame.buffer_mut();
        if let Some(effect) = self.accent_wave.as_mut() {
            effect.process(elapsed, buffer, area);
        }
        if let Some(effect) = self.sunlight_breathe.as_mut() {
            effect.process(elapsed, buffer, area);
        }
    }
}

fn main() -> Result<(), Box<dyn Error>> {
    let cli = parse_cli()?;
    let store = match cli.config {
        Some(path) => ConfigStore::new(path),
        None => ConfigStore::discover().map_err(other_error)?,
    };

    match cli.command {
        Some(Commands::Status { json, waybar }) => print_status(&store, json, waybar),
        Some(Commands::Config { command }) => configure(&store, command),
        Some(Commands::Doctor) => doctor(&store),
        Some(Commands::Help) => {
            print_help();
            Ok(())
        }
        Some(Commands::Version) => {
            println!("timescale {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        None => {
            let settings = store.load_or_create().map_err(other_error)?;
            run_tui(&store, settings)
        }
    }
}

fn parse_cli() -> Result<ParsedCli, Box<dyn Error>> {
    let mut arguments = env::args().skip(1).collect::<Vec<_>>();
    let mut config = None;
    let mut index = 0;
    while index < arguments.len() {
        if arguments[index] == "--config" {
            if index + 1 >= arguments.len() {
                return Err(other_error("--config requires a path".into()));
            }
            config = Some(PathBuf::from(arguments.remove(index + 1)));
            arguments.remove(index);
        } else {
            index += 1;
        }
    }

    let command = match arguments.as_slice() {
        [] => None,
        [flag] if flag == "--help" || flag == "-h" => Some(Commands::Help),
        [flag] if flag == "--version" || flag == "-V" => Some(Commands::Version),
        [command] if command == "status" => Some(Commands::Status {
            json: false,
            waybar: false,
        }),
        [command, flag] if command == "status" && flag == "--json" => Some(Commands::Status {
            json: true,
            waybar: false,
        }),
        [command, flag] if command == "status" && flag == "--waybar" => Some(Commands::Status {
            json: false,
            waybar: true,
        }),
        [command] if command == "doctor" => Some(Commands::Doctor),
        [command, subcommand] if command == "config" && subcommand == "path" => {
            Some(Commands::Config {
                command: ConfigCommand::Path,
            })
        }
        [command, subcommand] if command == "config" && subcommand == "show" => {
            Some(Commands::Config {
                command: ConfigCommand::Show,
            })
        }
        [command, subcommand] if command == "config" && subcommand == "edit" => {
            Some(Commands::Config {
                command: ConfigCommand::Edit,
            })
        }
        [command, subcommand, key, value] if command == "config" && subcommand == "set" => {
            Some(Commands::Config {
                command: ConfigCommand::Set {
                    key: key.clone(),
                    value: value.clone(),
                },
            })
        }
        _ => {
            return Err(other_error(format!(
                "unknown arguments: {}\nRun `timescale --help` for usage.",
                arguments.join(" ")
            )));
        }
    };
    Ok(ParsedCli { config, command })
}

fn print_help() {
    println!(
        "Timescale — see your time at a glance\n\n\
Usage:\n  timescale [--config PATH]\n  timescale status [--json|--waybar]\n  \
timescale config <path|show|edit>\n  timescale config set <KEY> <VALUE>\n  timescale doctor\n\n\
The interactive view updates automatically and uses q/Esc to quit or e to edit settings."
    );
}

fn print_status(
    store: &ConfigStore,
    json_output: bool,
    waybar: bool,
) -> Result<(), Box<dyn Error>> {
    let settings = store.load_or_create().map_err(other_error)?;
    let value = snapshot(&settings, Local::now()).map_err(other_error)?;
    if json_output {
        println!("{}", serde_json::to_string_pretty(&value)?);
    } else if waybar {
        let day = value
            .rows
            .iter()
            .find(|row| row.period == Period::Day)
            .ok_or_else(|| {
                other_error("the Day period must be visible for Waybar output".into())
            })?;
        let percent = day.elapsed * 100.0;
        let tooltip = value
            .rows
            .iter()
            .map(|row| {
                if row.period == Period::Life && row.start.is_empty() {
                    format!("{}: Not configured", row.title)
                } else {
                    format!("{}: {:.1}%", row.title, row.elapsed * 100.0)
                }
            })
            .collect::<Vec<_>>()
            .join("\n");
        let tooltip = value.routine.as_ref().map_or(tooltip.clone(), |routine| {
            format!(
                "{}: {:.1}%\n{tooltip}",
                routine.name,
                routine.elapsed * 100.0
            )
        });
        let class = if percent < 33.0 {
            "early"
        } else if percent < 67.0 {
            "middle"
        } else {
            "late"
        };
        println!(
            "{}",
            json!({
                "text": format!("⌛ {:.0}%", percent),
                "tooltip": tooltip,
                "class": class,
                "percentage": percent.round() as u8
            })
        );
    } else {
        println!("Timescale · {}", Local::now().format("%A, %b %-d · %H:%M"));
        if let Some(routine) = value.routine {
            println!(
                "{:<16} {:>6.1}%  {}",
                routine.name,
                routine.elapsed * 100.0,
                if routine.complete {
                    "complete".into()
                } else {
                    format!("{} left", duration_label(routine.remaining_seconds))
                }
            );
        }
        for row in value.rows {
            if row.period == Period::Life && row.start.is_empty() {
                println!(
                    "{:<16} {}",
                    row.title,
                    row.detail.as_deref().unwrap_or("Not configured")
                );
            } else {
                println!(
                    "{:<16} {:>6.1}%  {} left",
                    row.title,
                    row.elapsed * 100.0,
                    duration_label(row.remaining_seconds)
                );
            }
        }
        if let Some(solar) = value.solar {
            let sunrise = parse_date(&solar.sunrise)?;
            let sunset = parse_date(&solar.sunset)?;
            println!(
                "{:<16} {} – {}",
                "Sunlight",
                sunrise.format("%H:%M"),
                sunset.format("%H:%M")
            );
        }
    }
    Ok(())
}

fn configure(store: &ConfigStore, command: ConfigCommand) -> Result<(), Box<dyn Error>> {
    match command {
        ConfigCommand::Path => println!("{}", store.path().display()),
        ConfigCommand::Show => {
            let settings = store.load_or_create().map_err(other_error)?;
            println!("{}", serde_json::to_string_pretty(&settings)?);
        }
        ConfigCommand::Edit => edit_config(store)?,
        ConfigCommand::Set { key, value } => {
            let mut settings = store.load_or_create().map_err(other_error)?;
            set_value(&mut settings, &key, &value)?;
            store.save(&settings).map_err(other_error)?;
            println!("Updated {key} in {}", store.path().display());
        }
    }
    Ok(())
}

fn doctor(store: &ConfigStore) -> Result<(), Box<dyn Error>> {
    let settings = store.load_or_create().map_err(other_error)?;
    settings.validate().map_err(other_error)?;
    snapshot(&settings, Local::now()).map_err(other_error)?;
    println!("Settings: {}", store.path().display());
    println!("Schema:   version {}", settings.version);
    println!(
        "Terminal: {}",
        env::var("TERM").unwrap_or_else(|_| "unknown".into())
    );
    println!("Status:   OK");
    Ok(())
}

fn edit_config(store: &ConfigStore) -> Result<(), Box<dyn Error>> {
    store.load_or_create().map_err(other_error)?;
    let editor = env::var("VISUAL")
        .or_else(|_| env::var("EDITOR"))
        .unwrap_or_else(|_| if cfg!(windows) { "notepad" } else { "vi" }.into());
    let mut parts = editor.split_whitespace();
    let program = parts
        .next()
        .ok_or_else(|| other_error("editor command is empty".into()))?;
    let status = Command::new(program)
        .args(parts)
        .arg(store.path())
        .status()?;
    if !status.success() {
        return Err(other_error(format!("editor exited with {status}")));
    }
    store.load().map_err(other_error)?;
    Ok(())
}

fn set_value(settings: &mut Settings, key: &str, value: &str) -> Result<(), Box<dyn Error>> {
    match key {
        "day.start" => settings.day.start = value.into(),
        "day.end" => settings.day.end = value.into(),
        "routine.name" => settings.routine.name = value.into(),
        "routine.durationMinutes" => settings.routine.duration_minutes = value.parse()?,
        "routine.startedAt" => {
            settings.routine.started_at = if value == "null" || value.is_empty() {
                None
            } else {
                Some(value.into())
            }
        }
        "week.startsOn" => {
            settings.week.starts_on = match value {
                "monday" => WeekStart::Monday,
                "sunday" => WeekStart::Sunday,
                _ => return Err(other_error("week.startsOn must be monday or sunday".into())),
            }
        }
        "quarter.cycle" => {
            settings.quarter.cycle = match value {
                "calendar" => QuarterCycle::Calendar,
                "japanFiscal" => QuarterCycle::JapanFiscal,
                _ => {
                    return Err(other_error(
                        "quarter.cycle must be calendar or japanFiscal".into(),
                    ));
                }
            }
        }
        "solar.enabled" => settings.solar.enabled = parse_bool(value)?,
        "solar.latitude" => settings.solar.latitude = parse_optional_number(value)?,
        "solar.longitude" => settings.solar.longitude = parse_optional_number(value)?,
        "life.birthDate" => {
            settings.life.birth_date = if value == "null" || value.is_empty() {
                None
            } else {
                Some(value.into())
            }
        }
        "life.country" => settings.life.country = value.into(),
        "life.expectancyYears" => settings.life.expectancy_years = value.parse()?,
        "macOS.accent" => settings.mac_os.accent = value.into(),
        "macOS.precision" => settings.mac_os.precision = value.parse()?,
        "macOS.showRemaining" => settings.mac_os.show_remaining = parse_bool(value)?,
        "tui.theme" => {
            settings.tui.theme = match value {
                "auto" => TuiTheme::Auto,
                "color" => TuiTheme::Color,
                "catppuccin" => TuiTheme::Catppuccin,
                "tokyoNight" => TuiTheme::TokyoNight,
                "gruvbox" => TuiTheme::Gruvbox,
                "monochrome" => TuiTheme::Monochrome,
                _ => {
                    return Err(other_error(
                        "tui.theme must be auto, color, catppuccin, tokyoNight, gruvbox, or monochrome".into(),
                    ));
                }
            }
        }
        "tui.motion" => {
            settings.tui.motion = match value {
                "full" => TuiMotion::Full,
                "reduced" => TuiMotion::Reduced,
                "off" => TuiMotion::Off,
                _ => {
                    return Err(other_error(
                        "tui.motion must be full, reduced, or off".into(),
                    ));
                }
            }
        }
        "visible" => {
            settings.visible = if value.trim().is_empty() {
                Vec::new()
            } else {
                value
                    .split(',')
                    .map(parse_period)
                    .collect::<Result<Vec<_>, _>>()?
            };
        }
        _ => return Err(other_error(format!("unsupported setting {key:?}"))),
    }
    settings.validate().map_err(other_error)?;
    Ok(())
}

fn parse_bool(value: &str) -> Result<bool, Box<dyn Error>> {
    match value {
        "true" | "on" | "1" => Ok(true),
        "false" | "off" | "0" => Ok(false),
        _ => Err(other_error(format!("invalid boolean {value:?}"))),
    }
}

fn parse_optional_number(value: &str) -> Result<Option<f64>, Box<dyn Error>> {
    if value == "null" || value.is_empty() {
        Ok(None)
    } else {
        Ok(Some(value.parse()?))
    }
}

fn parse_period(value: &str) -> Result<Period, Box<dyn Error>> {
    match value.trim() {
        "day" => Ok(Period::Day),
        "week" => Ok(Period::Week),
        "month" => Ok(Period::Month),
        "quarter" => Ok(Period::Quarter),
        "year" => Ok(Period::Year),
        "life" => Ok(Period::Life),
        value => Err(other_error(format!("unknown period {value:?}"))),
    }
}

fn run_tui(store: &ConfigStore, settings: Settings) -> Result<(), Box<dyn Error>> {
    enable_raw_mode()?;
    let mut output = stdout();
    execute!(output, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(output);
    let mut terminal = Terminal::new(backend)?;
    let result = tui_loop(&mut terminal, store, settings);
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    result
}

fn tui_loop(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    store: &ConfigStore,
    mut settings: Settings,
) -> Result<(), Box<dyn Error>> {
    let launched = Instant::now();
    let mut last_frame = Instant::now();
    let mut last_reload = Instant::now();
    let mut reload_error = None;
    let mut effects = TuiEffects::new(&settings);
    let mut settings_menu: Option<SettingsMenu> = None;
    loop {
        if last_reload.elapsed() >= StdDuration::from_millis(500) {
            match store.load() {
                Ok(updated) => {
                    settings = updated;
                    reload_error = None;
                }
                Err(error) => reload_error = Some(error),
            }
            last_reload = Instant::now();
        }
        let value = snapshot(&settings, Local::now()).map_err(other_error)?;
        let elapsed_millis = launched.elapsed().as_millis() as u64;
        let (animation_tick, poll_interval) = match settings.tui.motion {
            TuiMotion::Full => (elapsed_millis / 140, StdDuration::from_millis(50)),
            TuiMotion::Reduced => (elapsed_millis / 650, StdDuration::from_millis(250)),
            TuiMotion::Off => (0, StdDuration::from_secs(1)),
        };
        effects.refresh_if_needed(&settings);
        let frame_elapsed = last_frame.elapsed();
        last_frame = Instant::now();
        terminal.draw(|frame| match &settings_menu {
            Some(menu) => menu.draw(frame, &settings, theme_palette(&settings)),
            None => {
                draw(
                    frame,
                    &value,
                    &settings,
                    animation_tick,
                    reload_error.as_deref(),
                );
                effects.render(frame, frame_elapsed);
            }
        })?;
        if event::poll(poll_interval)?
            && let Event::Key(key) = event::read()?
        {
            if key.kind != KeyEventKind::Press {
                continue;
            }
            if let Some(menu) = settings_menu.as_mut() {
                match menu.handle_key(key, &mut settings, store) {
                    MenuAction::Stay => {}
                    MenuAction::Close => settings_menu = None,
                    MenuAction::Quit => return Ok(()),
                }
                effects.refresh_if_needed(&settings);
            } else {
                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                    KeyCode::Char('e') => settings_menu = Some(SettingsMenu::new()),
                    KeyCode::Char('w') => {
                        if let Err(error) = toggle_routine(&mut settings, store, Local::now()) {
                            reload_error = Some(error);
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

fn toggle_routine(
    settings: &mut Settings,
    store: &ConfigStore,
    now: DateTime<Local>,
) -> Result<(), String> {
    let is_running = settings
        .routine
        .started_at
        .as_deref()
        .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
        .map(|start| start + Duration::minutes(i64::from(settings.routine.duration_minutes)) > now)
        .unwrap_or(false);
    let mut candidate = settings.clone();
    candidate.routine.started_at = if is_running {
        None
    } else {
        Some(now.to_rfc3339())
    };
    store.save(&candidate)?;
    *settings = candidate;
    Ok(())
}

fn draw(
    frame: &mut ratatui::Frame<'_>,
    snapshot: &Snapshot,
    settings: &Settings,
    animation_tick: u64,
    reload_error: Option<&str>,
) {
    let area = frame.area();
    let width = area.width.saturating_sub(6) as usize;
    let compact = area.height < 29;
    let spacious = area.height >= 36;
    let palette = theme_palette(settings);
    let accent = palette.accent;
    let solar_color = palette.solar;
    let primary = palette.primary;
    let muted = palette.muted;
    let title_style = Style::default().fg(primary).add_modifier(Modifier::BOLD);
    let date = Local::now().format("%A, %b %-d · %H:%M:%S").to_string();
    let brand = "    Timescale";
    let brand_width = brand.chars().count();
    let header_padding = width.saturating_sub(brand_width + date.chars().count());
    let mut lines = vec![
        Line::from(vec![
            Span::styled(brand, title_style),
            Span::raw(" ".repeat(header_padding.max(1))),
            Span::styled(date, Style::default().fg(muted)),
        ]),
        Line::default(),
    ];

    if let Some(routine) = &snapshot.routine {
        let percentage = format!(
            "{:.*}%",
            settings.mac_os.precision as usize,
            routine.elapsed * 100.0
        );
        let remaining = if routine.complete {
            "Complete".into()
        } else {
            format!("{} left", duration_label(routine.remaining_seconds))
        };
        let equivalence = format!("1% = {}", duration_label(routine.duration_seconds / 100.0));
        let routine_padding = width.saturating_sub(
            routine.name.chars().count()
                + remaining.chars().count()
                + equivalence.chars().count()
                + percentage.chars().count()
                + 6,
        );
        lines.push(Line::from(vec![
            Span::styled(routine.name.clone(), title_style),
            Span::raw("  "),
            Span::styled(remaining, Style::default().fg(muted)),
            Span::raw(" ".repeat(routine_padding.max(1))),
            Span::styled(equivalence, Style::default().fg(muted)),
            Span::raw("  "),
            Span::styled(percentage, title_style),
        ]));
        if !compact {
            lines.push(Line::default());
        }
        if let (Ok(start), Ok(end)) = (
            parse_date(&routine.started_at),
            parse_date(&routine.ends_at),
        ) {
            lines.push(Line::from(Span::styled(
                align(
                    &start.format("%H:%M").to_string(),
                    &end.format("%H:%M").to_string(),
                    width,
                ),
                Style::default().fg(muted),
            )));
        }
        lines.push(progress_line(routine.elapsed, None, width, accent, muted));
        lines.push(Line::default());
    }

    for row in &snapshot.rows {
        if row.period == Period::Life && row.start.is_empty() {
            let message = "Set a birth date in settings";
            let padding = width.saturating_sub("Life".len() + message.len());
            lines.push(Line::from(vec![
                Span::styled("Life", title_style),
                Span::raw(" ".repeat(padding.max(1))),
                Span::styled(message, Style::default().fg(muted)),
            ]));
            if !compact {
                lines.push(Line::default());
            }
            continue;
        }
        let displayed = if settings.mac_os.show_remaining {
            1.0 - row.elapsed
        } else {
            row.elapsed
        };
        let percentage = format!(
            "{:.*}%",
            settings.mac_os.precision as usize,
            displayed * 100.0
        );
        let detail = if row.period == Period::Life {
            row.detail.clone().unwrap_or_default()
        } else {
            String::new()
        };
        let remaining = format!("{} left", duration_label(row.remaining_seconds));
        let equivalence = format!("1% = {}", duration_label(row.one_percent_seconds));
        let detail_width = if detail.is_empty() {
            0
        } else {
            detail.chars().count() + 2
        };
        let left_width = row.title.chars().count() + detail_width + remaining.chars().count() + 2;
        let right_width = equivalence.chars().count() + percentage.chars().count() + 2;
        let left = if detail.is_empty() {
            format!("{}  {remaining}", row.title)
        } else {
            format!("{}  {detail}  {remaining}", row.title)
        };
        let right = format!("{equivalence}  {percentage}");
        let metadata_fits = left.chars().count() + right.chars().count() < width;
        if metadata_fits {
            let supporting = Style::default().fg(muted);
            let padding = width.saturating_sub(left_width + right_width);
            let mut spans = vec![Span::styled(row.title.clone(), title_style)];
            if !detail.is_empty() {
                spans.push(Span::raw("  "));
                spans.push(Span::styled(detail, supporting));
            }
            spans.push(Span::raw("  "));
            spans.push(Span::styled(remaining.clone(), supporting));
            spans.push(Span::raw(" ".repeat(padding.max(1))));
            spans.push(Span::styled(equivalence.clone(), supporting));
            spans.push(Span::raw("  "));
            spans.push(Span::styled(percentage.clone(), title_style));
            lines.push(Line::from(spans));
        } else {
            lines.push(Line::from(Span::styled(
                align(&row.title, &percentage, width),
                title_style,
            )));
        }
        if !compact {
            lines.push(Line::default());
        }
        if !metadata_fits && !compact {
            lines.push(Line::from(Span::styled(
                align(&remaining, &equivalence, width),
                Style::default().fg(muted),
            )));
        }
        if row.period == Period::Day {
            if let (Ok(start), Ok(end)) = (parse_date(&row.start), parse_date(&row.end)) {
                lines.push(Line::from(Span::styled(
                    align(
                        &start.format("%H:%M").to_string(),
                        &end.format("%H:%M").to_string(),
                        width,
                    ),
                    Style::default().fg(muted),
                )));
            }
        } else if row.period == Period::Quarter
            && let Some(range) = &row.detail
        {
            let mut parts = range.split(" – ");
            if let (Some(start), Some(end)) = (parts.next(), parts.next()) {
                lines.push(Line::from(Span::styled(
                    align(start, end, width),
                    Style::default().fg(muted),
                )));
            }
        }
        lines.push(progress_line(displayed, row.marker, width, accent, muted));
        if row.period == Period::Day
            && let Some(solar) = &snapshot.solar
        {
            lines.push(Line::default());
            let sunrise = parse_date(&solar.sunrise).ok();
            let sunset = parse_date(&solar.sunset).ok();
            if let (Some(sunrise), Some(sunset)) = (sunrise, sunset) {
                lines.push(Line::from(Span::styled(
                    align(
                        &format!("☀ {} sunrise", sunrise.format("%H:%M")),
                        &format!("{} sunset ☀", sunset.format("%H:%M")),
                        width,
                    ),
                    Style::default().fg(muted),
                )));
                lines.push(solar_line(
                    solar.sunrise_fraction,
                    solar.sunset_fraction,
                    width,
                    solar_color,
                    muted,
                ));
            }
        }
        if spacious {
            lines.push(Line::default());
        }
    }

    let routine_action = match &snapshot.routine {
        Some(routine) if routine.complete => format!("w restart {}", routine.name),
        Some(routine) => format!("w stop {}", routine.name),
        None => format!("w start {}", settings.routine.name),
    };
    let footer_left = reload_error.map_or_else(
        || format!("{routine_action} · e edit"),
        |error| format!("{routine_action} · e edit · {error}"),
    );
    lines.push(Line::from(Span::styled(
        align(&footer_left, "q quit", width),
        Style::default().fg(muted),
    )));
    let block = Block::default()
        .title(" time at a glance ")
        .borders(Borders::ALL)
        .padding(Padding::uniform(1));
    frame.render_widget(Paragraph::new(Text::from(lines)).block(block), area);

    let spinner_area = Rect::new(area.x.saturating_add(2), area.y.saturating_add(2), 2, 1);
    let spinner = match settings.tui.motion {
        TuiMotion::Full | TuiMotion::Reduced => {
            HOURGLASS_FRAMES[animation_tick as usize % HOURGLASS_FRAMES.len()]
        }
        TuiMotion::Off => HOURGLASS_FRAMES[0],
    };
    frame.render_widget(
        Paragraph::new(Span::styled(spinner, Style::default().fg(accent))),
        spinner_area,
    );
}

#[derive(Clone, Copy)]
struct ThemePalette {
    accent: Color,
    solar: Color,
    primary: Color,
    muted: Color,
}

fn theme_palette(settings: &Settings) -> ThemePalette {
    match settings.tui.theme {
        TuiTheme::Auto if env::var_os("NO_COLOR").is_some() => monochrome_palette(),
        TuiTheme::Monochrome => monochrome_palette(),
        TuiTheme::Auto | TuiTheme::Color => ThemePalette {
            accent: Color::Cyan,
            solar: Color::Yellow,
            primary: Color::White,
            muted: Color::DarkGray,
        },
        TuiTheme::Catppuccin => ThemePalette {
            accent: Color::Rgb(137, 180, 250),
            solar: Color::Rgb(249, 226, 175),
            primary: Color::Rgb(205, 214, 244),
            muted: Color::Rgb(127, 132, 156),
        },
        TuiTheme::TokyoNight => ThemePalette {
            accent: Color::Rgb(125, 207, 255),
            solar: Color::Rgb(224, 175, 104),
            primary: Color::Rgb(192, 202, 245),
            muted: Color::Rgb(115, 124, 153),
        },
        TuiTheme::Gruvbox => ThemePalette {
            accent: Color::Rgb(142, 192, 124),
            solar: Color::Rgb(250, 189, 47),
            primary: Color::Rgb(235, 219, 178),
            muted: Color::Rgb(168, 153, 132),
        },
    }
}

fn monochrome_palette() -> ThemePalette {
    ThemePalette {
        accent: Color::Reset,
        solar: Color::White,
        primary: Color::White,
        muted: Color::DarkGray,
    }
}

fn progress_line<'a>(
    elapsed: f64,
    marker: Option<f64>,
    width: usize,
    accent: Color,
    muted: Color,
) -> Line<'a> {
    let width = width.max(1);
    let filled = (elapsed.clamp(0.0, 1.0) * width as f64).round() as usize;
    let marker_index = marker
        .map(|value| (value.clamp(0.0, 1.0) * width.saturating_sub(1) as f64).round() as usize);
    Line::from(
        (0..width)
            .map(|index| {
                if marker_index == Some(index) {
                    Span::styled("◆", Style::default().fg(Color::White))
                } else if index < filled {
                    Span::styled("█", Style::default().fg(accent))
                } else {
                    Span::styled("░", Style::default().fg(muted))
                }
            })
            .collect::<Vec<_>>(),
    )
}

fn solar_line<'a>(sunrise: f64, sunset: f64, width: usize, solar: Color, muted: Color) -> Line<'a> {
    let width = width.max(1);
    let start = (sunrise.clamp(0.0, 1.0) * width as f64).round() as usize;
    let end = (sunset.clamp(0.0, 1.0) * width as f64).round() as usize;
    Line::from(
        (0..width)
            .map(|index| {
                if index >= start && index < end {
                    Span::styled("─", Style::default().fg(solar))
                } else {
                    Span::styled("·", Style::default().fg(muted))
                }
            })
            .collect::<Vec<_>>(),
    )
}

fn align(left: &str, right: &str, width: usize) -> String {
    let padding = width.saturating_sub(left.chars().count() + right.chars().count());
    format!("{left}{}{right}", " ".repeat(padding.max(1)))
}

fn duration_label(seconds: f64) -> String {
    let seconds = seconds.max(0.0);
    if seconds < 120.0 {
        format!("{} sec", seconds.round())
    } else if seconds < 3_600.0 {
        format!("{:.1} min", seconds / 60.0)
    } else if seconds < 172_800.0 {
        let total_minutes = (seconds / 60.0).round() as u64;
        let hours = total_minutes / 60;
        let minutes = total_minutes % 60;
        if minutes == 0 {
            format!("{hours}h")
        } else {
            format!("{hours}h {minutes}m")
        }
    } else if seconds < 5_184_000.0 {
        format!("{:.1} days", seconds / 86_400.0)
    } else if seconds < 63_115_200.0 {
        let days = seconds / 86_400.0;
        let months = (days / 30.436_875).floor();
        let remainder = (days - months * 30.436_875).round();
        format!("{months:.0}mo {remainder:.0}d")
    } else {
        let total_months = (seconds / 31_556_952.0 * 12.0).round() as u64;
        format!("{}y {}mo", total_months / 12, total_months % 12)
    }
}

fn parse_date(value: &str) -> Result<DateTime<Local>, Box<dyn Error>> {
    Ok(DateTime::parse_from_rfc3339(value)?.with_timezone(&Local))
}

fn other_error(message: String) -> Box<dyn Error> {
    Box::new(io::Error::other(message))
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use chrono::TimeZone;

    use super::*;

    #[test]
    fn renders_meaningful_durations() {
        assert_eq!(duration_label(90.0), "90 sec");
        assert_eq!(duration_label(3_600.0), "1h");
        assert_eq!(duration_label(9_000.0), "2h 30m");
    }

    #[test]
    fn progress_bar_includes_birthday_marker() {
        let line = progress_line(0.5, Some(0.75), 20, Color::Cyan, Color::DarkGray);
        assert!(line.spans.iter().any(|span| span.content.as_ref() == "◆"));
    }

    #[test]
    fn sunlight_bar_uses_a_thin_rule() {
        let line = solar_line(0.25, 0.75, 20, Color::Yellow, Color::DarkGray);
        let daylight = line
            .spans
            .iter()
            .filter(|span| span.content.as_ref() == "─")
            .count();
        assert_eq!(daylight, 10);
        assert!(!line.spans.iter().any(|span| span.content.as_ref() == "█"));
    }

    #[test]
    fn routine_action_starts_and_stops_atomically() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "timescale-routine-{}-{unique}.json",
            std::process::id()
        ));
        let store = ConfigStore::new(path.clone());
        let mut settings = Settings::default();
        let now = Local
            .with_ymd_and_hms(2026, 9, 6, 8, 0, 0)
            .single()
            .unwrap();

        toggle_routine(&mut settings, &store, now).unwrap();
        assert!(settings.routine.started_at.is_some());
        toggle_routine(&mut settings, &store, now).unwrap();
        assert!(settings.routine.started_at.is_none());
        assert!(store.load().unwrap().routine.started_at.is_none());

        fs::remove_file(path).unwrap();
    }
}
