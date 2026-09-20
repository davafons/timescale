use std::env;
use std::error::Error;
use std::io::{self, stdout};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration as StdDuration, Instant};

use chrono::{DateTime, Duration, Local, TimeZone, Timelike};
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
use serde::Deserialize;
use serde_json::json;
use tachyonfx::{CellFilter, Duration as FxDuration, Effect, Interpolation, fx};
use timescale_core::{
    ConfigStore, CounterSettings, InteractionCheck, Period, QuarterCycle, Settings, Snapshot,
    TuiMotion, TuiTheme, WeekStart, snapshot,
};

mod settings_ui;

use settings_ui::{MenuAction, SettingsMenu};

const HOURGLASS_FRAMES: [&str; 4] = ["⣹⣏", "⠹⣆", "⡷⢾", "⣰⠏"];

#[derive(Clone, Debug)]
struct CalendarEvent {
    id: i64,
    title: String,
    description: Option<String>,
    edit_url: Option<String>,
    start: DateTime<Local>,
    end: DateTime<Local>,
}

impl CalendarEvent {
    fn source(&self) -> String {
        format!("hey-event:{}", self.id)
    }

    fn progress(&self, now: DateTime<Local>) -> f64 {
        let duration = (self.end - self.start).num_milliseconds() as f64;
        if duration <= 0.0 {
            return f64::from(now >= self.end);
        }
        ((now - self.start).num_milliseconds() as f64 / duration).clamp(0.0, 1.0)
    }
}

#[derive(Deserialize)]
struct HeyEnvelope {
    data: Vec<HeyEvent>,
}

#[derive(Deserialize)]
struct HeyEvent {
    id: i64,
    title: Option<String>,
    summary: Option<String>,
    description: Option<String>,
    edit_url: Option<String>,
    starts_at: String,
    ends_at: String,
    all_day: Option<bool>,
}

struct HeyProvider {
    current: Option<CalendarEvent>,
    cached_events: Vec<CalendarEvent>,
    receiver: Option<Receiver<Vec<CalendarEvent>>>,
    last_refresh: Option<Instant>,
}

impl HeyProvider {
    fn new() -> Self {
        let mut provider = Self {
            current: None,
            cached_events: Vec::new(),
            receiver: None,
            last_refresh: None,
        };
        provider.refresh();
        provider
    }

    fn update(&mut self, now: DateTime<Local>) {
        if let Some(receiver) = &self.receiver
            && let Ok(events) = receiver.try_recv()
        {
            self.cached_events = events;
            self.receiver = None;
        }
        self.current = self
            .cached_events
            .iter()
            .filter(|event| now >= event.start && now < event.end)
            .min_by_key(|event| event.end)
            .cloned();
        if self.receiver.is_none()
            && self
                .last_refresh
                .is_none_or(|last| last.elapsed() >= StdDuration::from_secs(5 * 60))
        {
            self.refresh();
        }
    }

    fn refresh(&mut self) {
        let (sender, receiver) = mpsc::channel();
        std::thread::spawn(move || {
            let _ = sender.send(fetch_hey_events(Local::now()));
        });
        self.receiver = Some(receiver);
        self.last_refresh = Some(Instant::now());
    }
}

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
            let settings = record_tui_check(&store).map_err(other_error)?;
            run_tui(&store, settings)
        }
    }
}

fn record_tui_check(store: &ConfigStore) -> Result<Settings, String> {
    let timestamp = Local::now().timestamp_millis() as f64 / 1000.0;
    let app_name = env::var("TERM_PROGRAM")
        .ok()
        .or_else(|| Some("Terminal".into()));
    for _ in 0..3 {
        let mut settings = store.load_or_create()?;
        let expected = settings.clone();
        settings.record_check(InteractionCheck {
            timestamp,
            source: settings.mac_os.status_item_source.clone(),
            app_name: app_name.clone(),
            bundle_identifier: None,
        });
        match store.save_if_unchanged(&settings, &expected) {
            Ok(()) => return Ok(settings),
            Err(error) if error == "configuration changed externally; reload before saving" => {}
            Err(error) => return Err(error),
        }
    }
    Err("configuration kept changing externally; could not record this check-in".into())
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
The interactive view updates automatically. Use ↑/↓ to select, Page Up/Page Down to scroll, Enter to fold, s to select the status source, h for history, o to open a HEY event, w to start/pause, a to add, x to delete, r to reset, and e for settings.\n\
Counter config keys include counter.add, counter.delete, and counter.<id>.name/targetMinutes/elapsedMinutes/startedAt."
    );
}

fn print_status(
    store: &ConfigStore,
    json_output: bool,
    waybar: bool,
) -> Result<(), Box<dyn Error>> {
    let settings = store.load_or_create().map_err(other_error)?;
    let now = Local::now();
    let value = snapshot(&settings, now).map_err(other_error)?;
    let current_event = fetch_hey_events(now)
        .into_iter()
        .filter(|event| now >= event.start && now < event.end)
        .min_by_key(|event| event.end);
    if json_output {
        let mut output = serde_json::to_value(&value)?;
        if let serde_json::Value::Object(object) = &mut output {
            object.insert(
                "currentEvent".into(),
                current_event
                    .as_ref()
                    .map_or(serde_json::Value::Null, |event| {
                        json!({
                            "id": event.id,
                            "title": event.title,
                            "description": event.description,
                            "editUrl": event.edit_url,
                            "start": event.start.to_rfc3339(),
                            "end": event.end.to_rfc3339(),
                            "elapsed": event.progress(now),
                        })
                    }),
            );
        }
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else if waybar {
        let selected = settings.mac_os.status_item_source.as_str();
        let selected_counter = selected
            .strip_prefix("counter:")
            .and_then(|id| value.counters.iter().find(|counter| counter.id == id));
        let selected_row = match selected {
            "week" => value.rows.iter().find(|row| row.period == Period::Week),
            "month" => value.rows.iter().find(|row| row.period == Period::Month),
            "quarter" => value.rows.iter().find(|row| row.period == Period::Quarter),
            "year" => value.rows.iter().find(|row| row.period == Period::Year),
            "life" => value.rows.iter().find(|row| row.period == Period::Life),
            _ => value.rows.iter().find(|row| row.period == Period::Day),
        };
        let selected_row = selected_row
            .or_else(|| value.rows.iter().find(|row| row.period == Period::Day))
            .or_else(|| value.rows.first());
        let percent = selected_counter
            .map(|counter| counter.elapsed * 100.0)
            .or_else(|| selected_row.map(|row| row.elapsed * 100.0))
            .ok_or_else(|| other_error("the selected Waybar source is not visible".into()))?;
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
        let counter_tooltip = value
            .counters
            .iter()
            .map(|counter| format!("{}: {:.1}%", counter.name, counter.elapsed * 100.0))
            .collect::<Vec<_>>()
            .join("\n");
        let tooltip = if counter_tooltip.is_empty() {
            value.routine.as_ref().map_or(tooltip.clone(), |routine| {
                format!(
                    "{tooltip}\n{}: {:.1}%",
                    routine.name,
                    routine.elapsed * 100.0
                )
            })
        } else {
            format!("{tooltip}\n{counter_tooltip}")
        };
        let class = if percent < 33.0 {
            "early"
        } else if percent < 67.0 {
            "middle"
        } else {
            "late"
        };
        let event_text = current_event.as_ref().map_or(String::new(), |event| {
            format!("  📅 {:.0}%", event.progress(now) * 100.0)
        });
        let tooltip = if let Some(event) = &current_event {
            format!(
                "{tooltip}\n{}: {:.1}%",
                event.title,
                event.progress(now) * 100.0
            )
        } else {
            tooltip
        };
        println!(
            "{}",
            json!({
                "text": format!("⌛ {:.0}%{event_text}", percent),
                "tooltip": tooltip,
                "class": class,
                "percentage": percent.round() as u8
            })
        );
    } else {
        println!("Timescale · {}", Local::now().format("%A, %b %-d · %H:%M"));
        for row in &value.rows {
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
            if row.period == Period::Day
                && let Some(solar) = &value.solar
            {
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
        for counter in &value.counters {
            println!(
                "{:<16} {:>6.1}%  {}",
                counter.name,
                counter.elapsed * 100.0,
                if counter.complete {
                    "complete".into()
                } else if counter.running {
                    format!("{} left", duration_label(counter.remaining_seconds))
                } else {
                    "paused".into()
                }
            );
        }
        if let Some(routine) = &value.routine {
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
        if let Some(event) = current_event {
            println!(
                "{:<16} {:>6.1}%  {} – {}",
                event.title,
                event.progress(now) * 100.0,
                event.start.format("%H:%M"),
                event.end.format("%H:%M")
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
            let expected = settings.clone();
            set_value(&mut settings, &key, &value)?;
            store
                .save_if_unchanged(&settings, &expected)
                .map_err(other_error)?;
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
        "counter.add" => {
            let id = new_counter_id();
            settings.counters.push(CounterSettings {
                id,
                name: if value.trim().is_empty() {
                    "New counter".into()
                } else {
                    value.into()
                },
                target_minutes: 60,
                elapsed_seconds: 0.0,
                started_at: None,
            });
        }
        "counter.delete" => {
            settings.counters.retain(|counter| counter.id != value);
            settings
                .awareness
                .collapsed_sources
                .retain(|source| source != &format!("counter:{value}"));
            if settings.mac_os.status_item_source == format!("counter:{value}") {
                settings.mac_os.status_item_source = "day".into();
            }
        }
        key if key.starts_with("counter.") => {
            let remainder = &key["counter.".len()..];
            let (id, property) = remainder.split_once('.').ok_or_else(|| {
                other_error("use counter.<id>.<name|targetMinutes|elapsedMinutes|startedAt>".into())
            })?;
            let counter = settings
                .counters
                .iter_mut()
                .find(|counter| counter.id == id)
                .ok_or_else(|| other_error(format!("unknown counter {id:?}")))?;
            match property {
                "name" => counter.name = value.into(),
                "targetMinutes" => counter.target_minutes = value.parse()?,
                "elapsedMinutes" => counter.elapsed_seconds = value.parse::<f64>()? * 60.0,
                "startedAt" => {
                    counter.started_at = if value == "null" || value.is_empty() {
                        None
                    } else {
                        Some(value.into())
                    }
                }
                _ => {
                    return Err(other_error(format!(
                        "unsupported counter property {property:?}"
                    )));
                }
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
        "macOS.statusItemSource" => settings.mac_os.status_item_source = value.into(),
        "awareness.thresholdMinutes" => settings.awareness.threshold_minutes = value.parse()?,
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
    let mut selected_source = 0usize;
    let mut source_initialized = false;
    let mut show_history = false;
    let mut dashboard_scroll = 0u16;
    let mut history_scroll = 0u16;
    let mut hey_provider = HeyProvider::new();
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
        hey_provider.update(Local::now());
        let sources = dashboard_sources(&value, hey_provider.current.as_ref());
        if !source_initialized {
            selected_source = sources
                .iter()
                .position(|source| source == &settings.mac_os.status_item_source)
                .unwrap_or(0);
            source_initialized = true;
        }
        selected_source = selected_source.min(sources.len().saturating_sub(1));
        let elapsed_millis = launched.elapsed().as_millis() as u64;
        let (animation_tick, poll_interval) = match settings.tui.motion {
            TuiMotion::Full => (elapsed_millis / 140, StdDuration::from_millis(50)),
            TuiMotion::Reduced => (elapsed_millis / 650, StdDuration::from_millis(250)),
            TuiMotion::Off => (0, StdDuration::from_secs(1)),
        };
        effects.refresh_if_needed(&settings);
        let frame_elapsed = last_frame.elapsed();
        last_frame = Instant::now();
        terminal.draw(|frame| {
            if let Some(menu) = &settings_menu {
                menu.draw(frame, &settings, theme_palette(&settings));
            } else if show_history {
                history_scroll = draw_history(frame, &settings, history_scroll);
            } else {
                dashboard_scroll = draw(
                    frame,
                    &value,
                    &settings,
                    sources.get(selected_source).map(String::as_str),
                    hey_provider.current.as_ref(),
                    DashboardViewport {
                        animation_tick,
                        scroll: dashboard_scroll,
                    },
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
            } else if show_history {
                match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc | KeyCode::Char('h') => show_history = false,
                    KeyCode::PageUp => history_scroll = history_scroll.saturating_sub(5),
                    KeyCode::PageDown => history_scroll = history_scroll.saturating_add(5),
                    KeyCode::Home => history_scroll = 0,
                    _ => {}
                }
            } else {
                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                    KeyCode::Char('e') => settings_menu = Some(SettingsMenu::new()),
                    KeyCode::Char('h') => {
                        history_scroll = 0;
                        show_history = true;
                    }
                    KeyCode::PageUp => dashboard_scroll = dashboard_scroll.saturating_sub(5),
                    KeyCode::PageDown => dashboard_scroll = dashboard_scroll.saturating_add(5),
                    KeyCode::Home => dashboard_scroll = 0,
                    KeyCode::Up | KeyCode::Char('k') | KeyCode::Char('[') => {
                        selected_source = selected_source.saturating_sub(1);
                    }
                    KeyCode::Down | KeyCode::Char('j') | KeyCode::Char(']') => {
                        selected_source =
                            (selected_source + 1).min(sources.len().saturating_sub(1));
                    }
                    KeyCode::Enter | KeyCode::Char(' ') if !sources.is_empty() => {
                        let source = &sources[selected_source];
                        let mut candidate = settings.clone();
                        if let Some(index) = candidate
                            .awareness
                            .collapsed_sources
                            .iter()
                            .position(|value| value == source)
                        {
                            candidate.awareness.collapsed_sources.remove(index);
                        } else {
                            candidate.awareness.collapsed_sources.push(source.clone());
                            candidate.awareness.collapsed_sources.sort();
                            candidate.awareness.collapsed_sources.dedup();
                        }
                        if let Err(error) = store.save_if_unchanged(&candidate, &settings) {
                            reload_error = Some(error);
                        } else {
                            settings = candidate;
                        }
                    }
                    KeyCode::Char('s') if !sources.is_empty() => {
                        let source = &sources[selected_source];
                        if is_selectable_status_source(source, &value) {
                            let mut candidate = settings.clone();
                            candidate.mac_os.status_item_source = source.clone();
                            if let Err(error) = store.save_if_unchanged(&candidate, &settings) {
                                reload_error = Some(error);
                            } else {
                                settings = candidate;
                            }
                        }
                    }
                    KeyCode::Char('o') => {
                        if sources
                            .get(selected_source)
                            .is_some_and(|source| source.starts_with("hey-event:"))
                            && let Some(url) = hey_provider
                                .current
                                .as_ref()
                                .and_then(|event| event.edit_url.as_deref())
                            && let Err(error) = open_url(url)
                        {
                            reload_error = Some(error);
                        }
                    }
                    KeyCode::Char('a') => {
                        let id = new_counter_id();
                        let mut candidate = settings.clone();
                        candidate.counters.push(CounterSettings {
                            id,
                            name: "New counter".into(),
                            target_minutes: 60,
                            elapsed_seconds: 0.0,
                            started_at: None,
                        });
                        if let Err(error) = store.save_if_unchanged(&candidate, &settings) {
                            reload_error = Some(error);
                        } else {
                            settings = candidate;
                            selected_source =
                                value.rows.len() + settings.counters.len().saturating_sub(1);
                        }
                    }
                    KeyCode::Char('x') if !settings.counters.is_empty() => {
                        let Some(remove_index) =
                            selected_counter_index(&sources, selected_source, &settings)
                        else {
                            continue;
                        };
                        let mut candidate = settings.clone();
                        let removed_id = candidate.counters[remove_index].id.clone();
                        candidate.counters.remove(remove_index);
                        candidate
                            .awareness
                            .collapsed_sources
                            .retain(|source| source != &format!("counter:{removed_id}"));
                        if candidate.mac_os.status_item_source == format!("counter:{removed_id}") {
                            candidate.mac_os.status_item_source = "day".into();
                        }
                        if let Err(error) = store.save_if_unchanged(&candidate, &settings) {
                            reload_error = Some(error);
                        } else {
                            settings = candidate;
                            selected_source = selected_source.min(sources.len().saturating_sub(1));
                        }
                    }
                    KeyCode::Char('w') => {
                        let result = if settings.counters.is_empty() {
                            toggle_routine(&mut settings, store, Local::now())
                        } else if let Some(counter_index) =
                            selected_counter_index(&sources, selected_source, &settings)
                        {
                            toggle_counter(&mut settings, store, counter_index, Local::now())
                        } else {
                            Ok(())
                        };
                        if let Err(error) = result {
                            reload_error = Some(error);
                        }
                    }
                    KeyCode::Char('r') if !settings.counters.is_empty() => {
                        if let Some(index) =
                            selected_counter_index(&sources, selected_source, &settings)
                            && let Err(error) = reset_counter(&mut settings, store, index)
                        {
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
    store.save_if_unchanged(&candidate, settings)?;
    *settings = candidate;
    Ok(())
}

fn new_counter_id() -> String {
    format!(
        "counter-{}-{}",
        std::process::id(),
        chrono::Utc::now()
            .timestamp_nanos_opt()
            .unwrap_or_else(|| chrono::Utc::now().timestamp_micros() * 1_000)
    )
}

fn toggle_counter(
    settings: &mut Settings,
    store: &ConfigStore,
    index: usize,
    now: DateTime<Local>,
) -> Result<(), String> {
    let Some(counter) = settings.counters.get(index) else {
        return Ok(());
    };
    let current_elapsed = counter_elapsed(counter, now)?;
    let mut candidate = settings.clone();
    let counter = candidate.counters.get_mut(index).expect("index checked");
    if current_elapsed >= f64::from(counter.target_minutes) * 60.0 {
        counter.elapsed_seconds = 0.0;
        counter.started_at = Some(now.to_rfc3339());
    } else if counter.started_at.is_some() {
        counter.elapsed_seconds = current_elapsed;
        counter.started_at = None;
    } else {
        counter.started_at = Some(now.to_rfc3339());
    }
    store.save_if_unchanged(&candidate, settings)?;
    *settings = candidate;
    Ok(())
}

fn reset_counter(settings: &mut Settings, store: &ConfigStore, index: usize) -> Result<(), String> {
    if settings.counters.get(index).is_none() {
        return Ok(());
    }
    let mut candidate = settings.clone();
    let counter = candidate.counters.get_mut(index).expect("index checked");
    counter.elapsed_seconds = 0.0;
    counter.started_at = None;
    store.save_if_unchanged(&candidate, settings)?;
    *settings = candidate;
    Ok(())
}

fn counter_elapsed(counter: &CounterSettings, now: DateTime<Local>) -> Result<f64, String> {
    let Some(started_at) = counter.started_at.as_deref() else {
        return Ok(counter.elapsed_seconds);
    };
    let start = DateTime::parse_from_rfc3339(started_at)
        .map_err(|_| "counter.startedAt is invalid".to_string())?
        .with_timezone(&Local);
    Ok(
        (counter.elapsed_seconds + (now - start).num_milliseconds().max(0) as f64 / 1000.0)
            .min(f64::from(counter.target_minutes) * 60.0),
    )
}

fn period_source(period: Period) -> &'static str {
    match period {
        Period::Day => "day",
        Period::Week => "week",
        Period::Month => "month",
        Period::Quarter => "quarter",
        Period::Year => "year",
        Period::Life => "life",
    }
}

fn dashboard_sources(snapshot: &Snapshot, event: Option<&CalendarEvent>) -> Vec<String> {
    let mut sources = snapshot
        .rows
        .iter()
        .map(|row| period_source(row.period).to_string())
        .collect::<Vec<_>>();
    sources.extend(
        snapshot
            .counters
            .iter()
            .map(|counter| format!("counter:{}", counter.id)),
    );
    if let Some(event) = event {
        sources.push(event.source());
    }
    sources
}

fn selected_counter_index(
    sources: &[String],
    selected: usize,
    settings: &Settings,
) -> Option<usize> {
    let id = sources.get(selected)?.strip_prefix("counter:")?;
    settings
        .counters
        .iter()
        .position(|counter| counter.id == id)
}

fn is_selectable_status_source(source: &str, snapshot: &Snapshot) -> bool {
    if source.starts_with("hey-event:") {
        return false;
    }
    source != "life"
        || snapshot
            .rows
            .iter()
            .find(|row| row.period == Period::Life)
            .is_some_and(|row| !row.start.is_empty())
}

fn append_awareness_summary<'a>(
    lines: &mut Vec<Line<'a>>,
    settings: &Settings,
    width: usize,
    muted: Color,
) {
    let today = Local::now().date_naive();
    let mut checks = settings
        .awareness
        .checks
        .iter()
        .filter(|check| {
            Local
                .timestamp_millis_opt((check.timestamp * 1000.0) as i64)
                .single()
                .is_some_and(|date| date.date_naive() == today)
        })
        .collect::<Vec<_>>();
    checks.sort_by(|left, right| left.timestamp.total_cmp(&right.timestamp));
    if checks.is_empty() {
        return;
    }
    let (label, detail) = if checks.len() == 1 {
        (
            "First check today".to_string(),
            "0% since a prior check".to_string(),
        )
    } else {
        let latest = checks[checks.len() - 1];
        let previous = checks[checks.len() - 2];
        let seconds = (latest.timestamp - previous.timestamp).max(0.0);
        let day_minutes =
            day_duration_minutes(&settings.day.start, &settings.day.end).max(1) as f64;
        (
            format!("{} checks today", checks.len()),
            format!(
                "{} · {:.1}% since last check",
                duration_label(seconds),
                (seconds / (day_minutes * 60.0) * 100.0).clamp(0.0, 100.0)
            ),
        )
    };
    lines.push(Line::from(Span::styled(
        align(&label, &detail, width),
        Style::default().fg(muted),
    )));
    let explanation = if checks.len() == 1 {
        "Your next check will show the time and waking-day percentage since this one."
    } else {
        "Since last check"
    };
    lines.push(Line::from(Span::styled(
        if checks.len() == 1 {
            explanation.to_string()
        } else {
            align("", explanation, width)
        },
        Style::default().fg(muted),
    )));
    if checks.len() > 1 {
        let latest = checks[checks.len() - 1];
        let previous = checks[checks.len() - 2];
        if latest.timestamp - previous.timestamp
            >= f64::from(settings.awareness.threshold_minutes) * 60.0
        {
            lines.push(Line::from(Span::styled(
                "⚠ Longer than your reminder interval",
                Style::default().fg(Color::Yellow),
            )));
        }
    }
    lines.push(Line::default());
}

fn day_duration_minutes(start: &str, end: &str) -> u32 {
    let parse = |value: &str| {
        value.split_once(':').and_then(|(hour, minute)| {
            Some(hour.parse::<u32>().ok()? * 60 + minute.parse::<u32>().ok()?)
        })
    };
    match (parse(start), parse(end)) {
        (Some(start), Some(end)) if end > start => end - start,
        (Some(start), Some(end)) => 24 * 60 - start + end,
        _ => 24 * 60,
    }
}

fn draw_history(frame: &mut ratatui::Frame<'_>, settings: &Settings, scroll: u16) -> u16 {
    let area = frame.area();
    let palette = theme_palette(settings);
    let today = Local::now().date_naive();
    let mut checks = settings
        .awareness
        .checks
        .iter()
        .filter_map(|check| {
            let date = Local
                .timestamp_millis_opt((check.timestamp * 1000.0) as i64)
                .single()?;
            (date.date_naive() == today).then_some((check, date))
        })
        .collect::<Vec<_>>();
    checks.sort_by(|left, right| left.0.timestamp.total_cmp(&right.0.timestamp));
    let average = if checks.len() > 1 {
        let total = checks
            .windows(2)
            .map(|pair| pair[1].0.timestamp - pair[0].0.timestamp)
            .sum::<f64>();
        duration_label(total / (checks.len() - 1) as f64)
    } else {
        "—".into()
    };
    let mut hourly = [0usize; 24];
    for (_, date) in &checks {
        hourly[date.hour() as usize] += 1;
    }
    let maximum = hourly.iter().copied().max().unwrap_or(1).max(1);
    let chart = hourly
        .iter()
        .map(|count| match count * 4 / maximum {
            0 if *count == 0 => '·',
            0 | 1 => '▂',
            2 => '▄',
            3 => '▆',
            _ => '█',
        })
        .collect::<String>();
    let mut app_counts = std::collections::HashMap::<&str, usize>::new();
    for (check, _) in &checks {
        if let Some(name) = check.app_name.as_deref() {
            *app_counts.entry(name).or_default() += 1;
        }
    }
    let mut apps = app_counts.into_iter().collect::<Vec<_>>();
    apps.sort_by(|left, right| right.1.cmp(&left.1).then_with(|| left.0.cmp(right.0)));
    let mut lines = vec![
        Line::from(Span::styled(
            "Today’s checks",
            Style::default()
                .fg(palette.primary)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(format!(
            "{} times opened  ·  Average gap {average}",
            checks.len()
        )),
        Line::default(),
        Line::from(Span::styled(
            "Check-ins by hour",
            Style::default()
                .fg(palette.primary)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(chart, Style::default().fg(palette.accent))),
        Line::from(Span::styled(
            "12 AM    6 AM     Noon     6 PM",
            Style::default().fg(palette.muted),
        )),
    ];
    if !apps.is_empty() {
        lines.push(Line::default());
        lines.push(Line::from(Span::styled(
            "Frontmost apps at check-in",
            Style::default()
                .fg(palette.primary)
                .add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from(
            apps.into_iter()
                .take(4)
                .map(|(name, count)| format!("{name} {count}"))
                .collect::<Vec<_>>()
                .join("  ·  "),
        ));
    }
    lines.push(Line::default());
    lines.push(Line::from(Span::styled(
        "Check history",
        Style::default()
            .fg(palette.primary)
            .add_modifier(Modifier::BOLD),
    )));
    for (index, (check, date)) in checks.iter().enumerate().rev() {
        let interval = if index == 0 {
            "First today".into()
        } else {
            format!(
                "After {}",
                duration_label(check.timestamp - checks[index - 1].0.timestamp)
            )
        };
        let source = source_name(&check.source, settings);
        let app = check
            .app_name
            .as_deref()
            .map_or(String::new(), |name| format!(" · {name}"));
        lines.push(Line::from(vec![
            Span::styled(
                date.format("%H:%M").to_string(),
                Style::default().fg(palette.primary),
            ),
            Span::styled(
                format!("  {source}{app}"),
                Style::default().fg(palette.muted),
            ),
            Span::raw("  "),
            Span::styled(interval, Style::default().fg(palette.muted)),
        ]));
    }
    lines.push(Line::default());
    lines.push(Line::from(Span::styled(
        "PgUp/PgDn scroll · Home top · h/Esc back · q quit",
        Style::default().fg(palette.muted),
    )));
    let block = Block::default()
        .title(" history ")
        .borders(Borders::ALL)
        .padding(Padding::uniform(1));
    let inner = block.inner(area);
    let content_height = lines.len();
    let paragraph = Paragraph::new(lines).block(block);
    let max_scroll = content_height.saturating_sub(inner.height as usize) as u16;
    let scroll = scroll.min(max_scroll);
    frame.render_widget(paragraph.scroll((scroll, 0)), area);
    scroll
}

fn source_name(source: &str, settings: &Settings) -> String {
    if let Some(id) = source.strip_prefix("counter:") {
        return settings
            .counters
            .iter()
            .find(|counter| counter.id == id)
            .map(|counter| counter.name.clone())
            .unwrap_or_else(|| "Deleted counter".into());
    }
    match source {
        "day" => "Day",
        "week" => "Week",
        "month" => "Month",
        "quarter" => "Quarter",
        "year" => "Year",
        "life" => "Life",
        _ => "Unknown",
    }
    .into()
}

#[derive(Clone, Copy)]
struct DashboardViewport {
    animation_tick: u64,
    scroll: u16,
}

fn draw(
    frame: &mut ratatui::Frame<'_>,
    snapshot: &Snapshot,
    settings: &Settings,
    selected_source: Option<&str>,
    calendar_event: Option<&CalendarEvent>,
    viewport: DashboardViewport,
    reload_error: Option<&str>,
) -> u16 {
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
    let mut counter_lines = Vec::new();
    if !snapshot.counters.is_empty() {
        counter_lines.push(Line::from(Span::styled("Counters", title_style)));
    }

    for counter in &snapshot.counters {
        let source = format!("counter:{}", counter.id);
        let collapsed = settings.awareness.collapsed_sources.contains(&source);
        let percentage = format!(
            "{:.*}%",
            settings.mac_os.precision as usize,
            counter.elapsed * 100.0
        );
        let remaining = if counter.complete {
            "Complete".into()
        } else if counter.running {
            format!("{} left", duration_label(counter.remaining_seconds))
        } else {
            "Paused".into()
        };
        let marker = if selected_source == Some(source.as_str()) {
            "▶ "
        } else {
            "  "
        };
        let fold = if collapsed { "▸ " } else { "▾ " };
        let status = if settings.mac_os.status_item_source == source {
            " ★"
        } else {
            ""
        };
        counter_lines.push(Line::from(vec![
            Span::styled(format!("{marker}{fold}{}", counter.name), title_style),
            Span::raw("  "),
            Span::styled(remaining, Style::default().fg(muted)),
            Span::raw(" ".repeat(4)),
            Span::styled(format!("{percentage}{status}"), title_style),
        ]));
        if !collapsed {
            counter_lines.push(progress_line(counter.elapsed, None, width, accent, muted));
        }
        if !compact && !collapsed {
            counter_lines.push(Line::default());
        }
    }

    if let Some(routine) = &snapshot.routine {
        if snapshot.counters.is_empty() {
            counter_lines.push(Line::from(Span::styled("Routine", title_style)));
        }
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
        counter_lines.push(Line::from(vec![
            Span::styled(routine.name.clone(), title_style),
            Span::raw("  "),
            Span::styled(remaining, Style::default().fg(muted)),
            Span::raw(" ".repeat(routine_padding.max(1))),
            Span::styled(equivalence, Style::default().fg(muted)),
            Span::raw("  "),
            Span::styled(percentage, title_style),
        ]));
        if !compact {
            counter_lines.push(Line::default());
        }
        if let (Ok(start), Ok(end)) = (
            parse_date(&routine.started_at),
            parse_date(&routine.ends_at),
        ) {
            counter_lines.push(Line::from(Span::styled(
                align(
                    &start.format("%H:%M").to_string(),
                    &end.format("%H:%M").to_string(),
                    width,
                ),
                Style::default().fg(muted),
            )));
        }
        counter_lines.push(progress_line(routine.elapsed, None, width, accent, muted));
        counter_lines.push(Line::default());
    }

    for row in &snapshot.rows {
        let source = period_source(row.period);
        let collapsed = settings
            .awareness
            .collapsed_sources
            .iter()
            .any(|value| value == source);
        let selection = if selected_source == Some(source) {
            "▶ "
        } else {
            "  "
        };
        let fold = if collapsed { "▸ " } else { "▾ " };
        let status = if settings.mac_os.status_item_source == source {
            " ★"
        } else {
            ""
        };
        if row.period == Period::Life && row.start.is_empty() {
            let message = "Set a birth date in settings";
            let padding = width.saturating_sub("Life".len() + message.len());
            lines.push(Line::from(vec![
                Span::styled(format!("{selection}{fold}Life"), title_style),
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
        let left_width = selection.chars().count()
            + fold.chars().count()
            + row.title.chars().count()
            + detail_width
            + remaining.chars().count()
            + 2;
        let right_width =
            equivalence.chars().count() + percentage.chars().count() + status.chars().count() + 2;
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
            let mut spans = vec![Span::styled(
                format!("{selection}{fold}{}", row.title),
                title_style,
            )];
            if !detail.is_empty() {
                spans.push(Span::raw("  "));
                spans.push(Span::styled(detail, supporting));
            }
            spans.push(Span::raw("  "));
            spans.push(Span::styled(remaining.clone(), supporting));
            spans.push(Span::raw(" ".repeat(padding.max(1))));
            spans.push(Span::styled(equivalence.clone(), supporting));
            spans.push(Span::raw("  "));
            spans.push(Span::styled(format!("{percentage}{status}"), title_style));
            lines.push(Line::from(spans));
        } else {
            lines.push(Line::from(Span::styled(
                align(
                    &format!("{selection}{fold}{}", row.title),
                    &format!("{percentage}{status}"),
                    width,
                ),
                title_style,
            )));
        }
        if collapsed {
            continue;
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

    if !counter_lines.is_empty() {
        lines.push(section_divider(width, muted));
        lines.extend(counter_lines);
    }

    if let Some(event) = calendar_event {
        lines.push(section_divider(width, muted));
        let source = event.source();
        let selected = selected_source == Some(source.as_str());
        let collapsed = settings.awareness.collapsed_sources.contains(&source);
        let elapsed = event.progress(Local::now());
        let remaining = (event.end - Local::now()).num_seconds().max(0) as f64;
        let event_percentage = format!(
            "{:.*}%",
            settings.mac_os.precision as usize,
            elapsed * 100.0
        );
        let prefix = format!(
            "{}{}",
            if selected { "▶ " } else { "  " },
            if collapsed { "▸ " } else { "▾ " }
        );
        let available_title =
            width.saturating_sub(prefix.chars().count() + event_percentage.chars().count() + 1);
        let display_title = truncate_text(&event.title, available_title);
        let event_padding = width.saturating_sub(
            prefix.chars().count()
                + display_title.chars().count()
                + event_percentage.chars().count(),
        );
        lines.push(Line::from(vec![
            Span::styled(format!("{prefix}{display_title}"), title_style),
            Span::raw(" ".repeat(event_padding.max(1))),
            Span::styled(event_percentage, title_style),
        ]));
        lines.push(Line::from(Span::styled(
            format!("HEY event · {} left", duration_label(remaining)),
            Style::default().fg(muted),
        )));
        if !collapsed {
            lines.push(Line::from(Span::styled(
                align(
                    &event.start.format("%H:%M").to_string(),
                    &event.end.format("%H:%M").to_string(),
                    width,
                ),
                Style::default().fg(muted),
            )));
            lines.push(progress_line(elapsed, None, width, accent, muted));
            if let Some(description) = event
                .description
                .as_deref()
                .filter(|value| !value.trim().is_empty())
            {
                lines.push(Line::from(Span::styled(
                    description,
                    Style::default().fg(muted),
                )));
            }
        }
        lines.push(Line::default());
    }

    let mut awareness_lines = Vec::new();
    append_awareness_summary(&mut awareness_lines, settings, width, muted);
    if !awareness_lines.is_empty() {
        lines.push(section_divider(width, muted));
        lines.extend(awareness_lines);
    }

    let selected_counter = selected_source
        .and_then(|source| source.strip_prefix("counter:"))
        .and_then(|id| snapshot.counters.iter().find(|counter| counter.id == id));
    let routine_action = match selected_counter {
        Some(counter) if counter.complete => format!("w restart {}", counter.name),
        Some(counter) if counter.running => format!("w pause {}", counter.name),
        Some(counter) => format!("w start {}", counter.name),
        None if !snapshot.counters.is_empty() => "select a counter for w".into(),
        None => match &snapshot.routine {
            Some(routine) if routine.complete => format!("w restart {}", routine.name),
            Some(routine) => format!("w stop {}", routine.name),
            None => format!("w start {}", settings.routine.name),
        },
    };
    let footer_left = reload_error.map_or_else(
        || {
            format!(
                "{routine_action} · ↑/↓ select · PgUp/PgDn scroll · Enter fold · s status · h history · e settings"
            )
        },
        |error| {
            format!("{routine_action} · ↑/↓ select · Enter fold · s status · h history · {error}")
        },
    );
    lines.push(section_divider(width, muted));
    lines.push(Line::from(Span::styled(
        align(&footer_left, "q quit", width),
        Style::default().fg(muted),
    )));
    let block = Block::default()
        .title(" time at a glance ")
        .borders(Borders::ALL)
        .padding(Padding::uniform(1));
    let inner = block.inner(area);
    let content_height = lines.len();
    let paragraph = Paragraph::new(Text::from(lines)).block(block);
    let max_scroll = content_height.saturating_sub(inner.height as usize) as u16;
    let scroll = viewport.scroll.min(max_scroll);
    frame.render_widget(paragraph.scroll((scroll, 0)), area);

    let spinner_area = Rect::new(area.x.saturating_add(2), area.y.saturating_add(2), 2, 1);
    let spinner = match settings.tui.motion {
        TuiMotion::Full | TuiMotion::Reduced => {
            HOURGLASS_FRAMES[viewport.animation_tick as usize % HOURGLASS_FRAMES.len()]
        }
        TuiMotion::Off => HOURGLASS_FRAMES[0],
    };
    frame.render_widget(
        Paragraph::new(Span::styled(spinner, Style::default().fg(accent))),
        spinner_area,
    );
    scroll
}

fn section_divider<'a>(width: usize, muted: Color) -> Line<'a> {
    Line::from(Span::styled("─".repeat(width), Style::default().fg(muted)))
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

fn truncate_text(value: &str, width: usize) -> String {
    if value.chars().count() <= width {
        return value.to_string();
    }
    if width <= 1 {
        return "…".chars().take(width).collect();
    }
    value
        .chars()
        .take(width - 1)
        .chain(std::iter::once('…'))
        .collect()
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

fn fetch_hey_events(now: DateTime<Local>) -> Vec<CalendarEvent> {
    let Some(executable) = hey_executable() else {
        return Vec::new();
    };
    let output = Command::new(executable)
        .args([
            "event",
            "list",
            "--starts-on",
            &(now - Duration::days(1)).format("%Y-%m-%d").to_string(),
            "--ends-on",
            &(now + Duration::days(1)).format("%Y-%m-%d").to_string(),
            "--all",
            "--json",
        ])
        .stderr(Stdio::null())
        .output();
    let Ok(output) = output else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    parse_hey_events(&output.stdout)
}

fn parse_hey_events(data: &[u8]) -> Vec<CalendarEvent> {
    let Ok(envelope) = serde_json::from_slice::<HeyEnvelope>(data) else {
        return Vec::new();
    };
    envelope
        .data
        .into_iter()
        .filter(|event| event.all_day != Some(true))
        .filter_map(|event| {
            let start = DateTime::parse_from_rfc3339(&event.starts_at)
                .ok()?
                .with_timezone(&Local);
            let end = DateTime::parse_from_rfc3339(&event.ends_at)
                .ok()?
                .with_timezone(&Local);
            (end > start).then_some(CalendarEvent {
                id: event.id,
                title: event
                    .title
                    .or(event.summary)
                    .unwrap_or_else(|| "Untitled event".into()),
                description: event.description,
                edit_url: event.edit_url,
                start,
                end,
            })
        })
        .collect()
}

fn hey_executable() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(home) = env::var_os("HOME") {
        candidates.push(PathBuf::from(home).join(".local/bin/hey"));
    }
    candidates.push(PathBuf::from("/opt/homebrew/bin/hey"));
    candidates.push(PathBuf::from("/usr/local/bin/hey"));
    if let Some(path) = env::var_os("PATH") {
        candidates.extend(
            env::split_paths(&path)
                .map(|directory| directory.join(if cfg!(windows) { "hey.exe" } else { "hey" })),
        );
    }
    candidates.into_iter().find(|path| path.is_file())
}

fn open_url(url: &str) -> Result<(), String> {
    let (program, arguments): (&str, Vec<&str>) = if cfg!(target_os = "macos") {
        ("open", vec![url])
    } else if cfg!(windows) {
        ("rundll32", vec!["url.dll,FileProtocolHandler", url])
    } else {
        ("xdg-open", vec![url])
    };
    let mut child = Command::new(program)
        .args(arguments)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("Could not open event: {error}"))?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}

fn other_error(message: String) -> Box<dyn Error> {
    Box::new(io::Error::other(message))
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use chrono::TimeZone;
    use ratatui::backend::TestBackend;

    use super::*;

    #[test]
    fn renders_meaningful_durations() {
        assert_eq!(duration_label(90.0), "90 sec");
        assert_eq!(duration_label(3_600.0), "1h");
        assert_eq!(duration_label(9_000.0), "2h 30m");
    }

    #[test]
    fn long_event_titles_fit_the_available_width() {
        assert_eq!(truncate_text("Calendar focus session", 10), "Calendar …");
        assert_eq!(truncate_text("Focus", 10), "Focus");
    }

    #[test]
    fn dashboard_marks_the_selected_status_source_and_collapsed_rows() {
        let mut settings = Settings::default();
        settings.awareness.collapsed_sources.push("day".into());
        let value = snapshot(&settings, Local::now()).unwrap();
        let mut terminal = Terminal::new(TestBackend::new(100, 32)).unwrap();
        terminal
            .draw(|frame| {
                let _ = draw(
                    frame,
                    &value,
                    &settings,
                    Some("day"),
                    None,
                    DashboardViewport {
                        animation_tick: 0,
                        scroll: 0,
                    },
                    None,
                );
            })
            .unwrap();
        let buffer = terminal.backend().buffer();
        let rendered = (0..buffer.area.height)
            .map(|y| {
                (0..buffer.area.width)
                    .map(|x| buffer[(x, y)].symbol())
                    .collect::<String>()
            })
            .collect::<Vec<_>>()
            .join("\n");
        assert!(rendered.contains("▶ ▸ Day"));
        assert!(rendered.contains('★'));
    }

    #[test]
    fn dashboard_navigation_follows_the_native_section_order() {
        let mut settings = Settings::default();
        settings.counters.push(CounterSettings {
            id: "focus".into(),
            name: "Focus".into(),
            target_minutes: 60,
            elapsed_seconds: 0.0,
            started_at: None,
        });
        let value = snapshot(&settings, Local::now()).unwrap();
        let event_start = Local::now();
        let event = CalendarEvent {
            id: 7,
            title: "Meeting".into(),
            description: None,
            edit_url: None,
            start: event_start,
            end: event_start + Duration::hours(1),
        };

        let sources = dashboard_sources(&value, Some(&event));
        let counter_index = sources
            .iter()
            .position(|source| source == "counter:focus")
            .unwrap();
        let event_index = sources
            .iter()
            .position(|source| source == "hey-event:7")
            .unwrap();

        assert_eq!(sources.first().map(String::as_str), Some("day"));
        assert!(counter_index > sources.iter().position(|source| source == "life").unwrap());
        assert!(event_index > counter_index);
    }

    #[test]
    fn dashboard_renders_native_section_order_borders_and_check_context() {
        let mut settings = Settings::default();
        settings.counters.push(CounterSettings {
            id: "focus".into(),
            name: "Focus".into(),
            target_minutes: 60,
            elapsed_seconds: 0.0,
            started_at: None,
        });
        settings.record_check(InteractionCheck {
            timestamp: Local::now().timestamp_millis() as f64 / 1000.0,
            source: "day".into(),
            app_name: Some("Terminal".into()),
            bundle_identifier: None,
        });
        let value = snapshot(&settings, Local::now()).unwrap();
        let mut terminal = Terminal::new(TestBackend::new(120, 60)).unwrap();
        terminal
            .draw(|frame| {
                let _ = draw(
                    frame,
                    &value,
                    &settings,
                    Some("day"),
                    None,
                    DashboardViewport {
                        animation_tick: 0,
                        scroll: 0,
                    },
                    None,
                );
            })
            .unwrap();
        let buffer = terminal.backend().buffer();
        let rendered = (0..buffer.area.height)
            .map(|y| {
                (0..buffer.area.width)
                    .map(|x| buffer[(x, y)].symbol())
                    .collect::<String>()
            })
            .collect::<Vec<_>>()
            .join("\n");

        let day = rendered.find("Day").unwrap();
        let counters = rendered.find("Counters").unwrap();
        let checks = rendered.find("First check today").unwrap();
        assert!(day < counters && counters < checks);
        assert!(rendered.contains("Your next check will show the time"));
        assert!(rendered.lines().any(|line| line.contains("─────")));
    }

    #[test]
    fn status_selection_excludes_events_and_an_unconfigured_life() {
        let mut settings = Settings::default();
        let now = Local
            .with_ymd_and_hms(2026, 9, 20, 12, 0, 0)
            .single()
            .unwrap();
        let value = snapshot(&settings, now).unwrap();
        assert!(!is_selectable_status_source("life", &value));
        assert!(!is_selectable_status_source("hey-event:7", &value));

        settings.life.birth_date = Some("1990-01-01".into());
        let value = snapshot(&settings, now).unwrap();
        assert!(is_selectable_status_source("life", &value));
    }

    #[test]
    fn hey_provider_selects_the_next_cached_event_without_refetching() {
        let first_start = Local
            .with_ymd_and_hms(2026, 9, 20, 9, 0, 0)
            .single()
            .unwrap();
        let second_start = first_start + Duration::hours(1);
        let event = |id, title: &str, start| CalendarEvent {
            id,
            title: title.into(),
            description: None,
            edit_url: None,
            start,
            end: start + Duration::hours(1),
        };
        let mut provider = HeyProvider {
            current: None,
            cached_events: vec![
                event(1, "First", first_start),
                event(2, "Second", second_start),
            ],
            receiver: None,
            last_refresh: Some(Instant::now()),
        };
        provider.update(first_start + Duration::minutes(30));
        assert_eq!(provider.current.as_ref().map(|event| event.id), Some(1));
        provider.update(second_start + Duration::minutes(30));
        assert_eq!(provider.current.as_ref().map(|event| event.id), Some(2));
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
    fn hey_payload_keeps_timed_events_and_the_edit_link() {
        let events = parse_hey_events(
            br#"{"data":[{"id":7,"title":"Focus","summary":null,"description":"Deep work","edit_url":"https://app.hey.com/calendar/events/7","starts_at":"2026-09-20T09:00:00+09:00","ends_at":"2026-09-20T10:00:00+09:00","all_day":false},{"id":8,"title":"Holiday","summary":null,"description":null,"edit_url":null,"starts_at":"2026-09-20T00:00:00+09:00","ends_at":"2026-09-21T00:00:00+09:00","all_day":true}]}"#,
        );
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].title, "Focus");
        assert_eq!(
            events[0].edit_url.as_deref(),
            Some("https://app.hey.com/calendar/events/7")
        );
        let halfway = DateTime::parse_from_rfc3339("2026-09-20T09:30:00+09:00")
            .unwrap()
            .with_timezone(&Local);
        assert!((events[0].progress(halfway) - 0.5).abs() < 0.0001);
    }

    #[test]
    fn waking_day_percentage_supports_overnight_schedules() {
        assert_eq!(day_duration_minutes("08:00", "23:00"), 15 * 60);
        assert_eq!(day_duration_minutes("22:00", "06:00"), 8 * 60);
        assert_eq!(day_duration_minutes("08:00", "08:00"), 24 * 60);
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
