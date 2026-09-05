use std::collections::HashSet;
use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use chrono::{
    DateTime, Datelike, Duration, Local, LocalResult, NaiveDate, TimeZone, Timelike, Utc,
};
use serde::{Deserialize, Serialize};

pub const CONFIG_VERSION: u32 = 1;
static SAVE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
pub struct Settings {
    pub version: u32,
    pub time_zone: String,
    pub day: DaySettings,
    pub routine: RoutineSettings,
    pub week: WeekSettings,
    pub quarter: QuarterSettings,
    pub solar: SolarSettings,
    pub life: LifeSettings,
    pub visible: Vec<Period>,
    #[serde(rename = "macOS")]
    pub mac_os: MacOsSettings,
    pub tui: TuiSettings,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            version: CONFIG_VERSION,
            time_zone: "local".into(),
            day: DaySettings::default(),
            routine: RoutineSettings::default(),
            week: WeekSettings::default(),
            quarter: QuarterSettings::default(),
            solar: SolarSettings::default(),
            life: LifeSettings::default(),
            visible: Period::ALL.to_vec(),
            mac_os: MacOsSettings::default(),
            tui: TuiSettings::default(),
        }
    }
}

impl Settings {
    pub fn validate(&self) -> Result<(), String> {
        if self.version != CONFIG_VERSION {
            return Err(format!(
                "unsupported configuration version {}; expected {CONFIG_VERSION}",
                self.version
            ));
        }
        if self.time_zone != "local" {
            return Err("timeZone currently must be \"local\"".into());
        }
        parse_time(&self.day.start)?;
        parse_time(&self.day.end)?;
        if self.routine.name.trim().is_empty() {
            return Err("routine.name must not be empty".into());
        }
        if !(1..=10_080).contains(&self.routine.duration_minutes) {
            return Err("routine.durationMinutes must be between 1 and 10080".into());
        }
        if let Some(started_at) = &self.routine.started_at {
            DateTime::parse_from_rfc3339(started_at)
                .map_err(|_| "routine.startedAt must be an RFC 3339 timestamp".to_string())?;
        }
        if !(0..=3).contains(&self.mac_os.precision) {
            return Err("macOS.precision must be between 0 and 3".into());
        }
        if !(0.0..=150.0).contains(&self.life.expectancy_years) || self.life.expectancy_years == 0.0
        {
            return Err("life.expectancyYears must be greater than 0 and at most 150".into());
        }
        if let Some(value) = self.solar.latitude
            && !(-90.0..=90.0).contains(&value)
        {
            return Err("solar.latitude must be between -90 and 90".into());
        }
        if let Some(value) = self.solar.longitude
            && !(-180.0..=180.0).contains(&value)
        {
            return Err("solar.longitude must be between -180 and 180".into());
        }
        if self.solar.latitude.is_some() != self.solar.longitude.is_some() {
            return Err(
                "solar.latitude and solar.longitude must both be set or both be null".into(),
            );
        }
        if let Some(value) = &self.life.birth_date {
            NaiveDate::parse_from_str(value, "%Y-%m-%d")
                .map_err(|_| "life.birthDate must use YYYY-MM-DD".to_string())?;
        }
        if self.visible.iter().collect::<HashSet<_>>().len() != self.visible.len() {
            return Err("visible must not contain duplicate periods".into());
        }
        if !matches!(
            self.mac_os.accent.as_str(),
            "system" | "orange" | "blue" | "green" | "purple" | "monochrome"
        ) {
            return Err("macOS.accent is not supported".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
pub struct DaySettings {
    pub start: String,
    pub end: String,
}

impl Default for DaySettings {
    fn default() -> Self {
        Self {
            start: "08:00".into(),
            end: "23:00".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
pub struct RoutineSettings {
    pub name: String,
    pub duration_minutes: u32,
    pub started_at: Option<String>,
}

impl Default for RoutineSettings {
    fn default() -> Self {
        Self {
            name: "Work".into(),
            duration_minutes: 8 * 60,
            started_at: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum WeekStart {
    Monday,
    Sunday,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
pub struct WeekSettings {
    pub starts_on: WeekStart,
}

impl Default for WeekSettings {
    fn default() -> Self {
        Self {
            starts_on: WeekStart::Monday,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum QuarterCycle {
    Calendar,
    JapanFiscal,
}

impl QuarterCycle {
    pub fn start_month(&self) -> u32 {
        match self {
            Self::Calendar => 1,
            Self::JapanFiscal => 4,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
pub struct QuarterSettings {
    pub cycle: QuarterCycle,
}

impl Default for QuarterSettings {
    fn default() -> Self {
        Self {
            cycle: QuarterCycle::Calendar,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
pub struct SolarSettings {
    pub enabled: bool,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
}

impl Default for SolarSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            latitude: None,
            longitude: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
pub struct LifeSettings {
    pub birth_date: Option<String>,
    pub country: String,
    pub expectancy_years: f64,
}

impl Default for LifeSettings {
    fn default() -> Self {
        Self {
            birth_date: None,
            country: "Japan".into(),
            expectancy_years: 84.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
pub struct MacOsSettings {
    pub accent: String,
    pub precision: u8,
    pub show_remaining: bool,
}

impl Default for MacOsSettings {
    fn default() -> Self {
        Self {
            accent: "system".into(),
            precision: 1,
            show_remaining: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
pub struct TuiSettings {
    pub theme: TuiTheme,
    pub motion: TuiMotion,
}

impl Default for TuiSettings {
    fn default() -> Self {
        Self {
            theme: TuiTheme::Auto,
            motion: TuiMotion::Full,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum TuiTheme {
    Auto,
    Color,
    Catppuccin,
    TokyoNight,
    Gruvbox,
    Monochrome,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum TuiMotion {
    Full,
    Reduced,
    Off,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum Period {
    Day,
    Week,
    Month,
    Quarter,
    Year,
    Life,
}

impl Period {
    pub const ALL: [Self; 6] = [
        Self::Day,
        Self::Week,
        Self::Month,
        Self::Quarter,
        Self::Year,
        Self::Life,
    ];
}

#[derive(Debug, Clone)]
pub struct ConfigStore {
    path: PathBuf,
}

impl ConfigStore {
    pub fn discover() -> Result<Self, String> {
        Ok(Self::new(config_path()?))
    }

    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn load_or_create(&self) -> Result<Settings, String> {
        if self.path.exists() {
            let settings = self.load()?;
            #[cfg(target_os = "macos")]
            if settings == Settings::default()
                && let Some(imported) = settings_from_macos_defaults()
                && imported != settings
            {
                self.save(&imported)?;
                return Ok(imported);
            }
            Ok(settings)
        } else {
            #[cfg(target_os = "macos")]
            let settings = settings_from_macos_defaults().unwrap_or_default();
            #[cfg(not(target_os = "macos"))]
            let settings = Settings::default();
            self.save(&settings)?;
            Ok(settings)
        }
    }

    pub fn load(&self) -> Result<Settings, String> {
        let data = fs::read(&self.path)
            .map_err(|error| format!("could not read {}: {error}", self.path.display()))?;
        let settings: Settings = serde_json::from_slice(&data).map_err(|error| {
            format!("invalid configuration in {}: {error}", self.path.display())
        })?;
        settings.validate()?;
        Ok(settings)
    }

    pub fn save(&self, settings: &Settings) -> Result<(), String> {
        settings.validate()?;
        let parent = self
            .path
            .parent()
            .ok_or_else(|| "configuration path has no parent directory".to_string())?;
        fs::create_dir_all(parent)
            .map_err(|error| format!("could not create {}: {error}", parent.display()))?;
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let target_name = self
            .path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("config.json");
        let (temporary_path, mut temporary) = loop {
            let sequence = SAVE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = parent.join(format!(
                ".{target_name}.{}.{}.tmp",
                std::process::id(),
                sequence
            ));
            match options.open(&path) {
                Ok(file) => break (path, file),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => {
                    return Err(format!("could not create temporary settings file: {error}"));
                }
            }
        };
        serde_json::to_writer_pretty(&mut temporary, settings)
            .map_err(|error| format!("could not encode settings: {error}"))?;
        temporary
            .write_all(b"\n")
            .map_err(|error| format!("could not finish settings file: {error}"))?;
        temporary
            .sync_all()
            .map_err(|error| format!("could not sync settings file: {error}"))?;
        drop(temporary);
        #[cfg(windows)]
        if self.path.exists() {
            fs::remove_file(&self.path)
                .map_err(|error| format!("could not replace {}: {error}", self.path.display()))?;
        }
        fs::rename(&temporary_path, &self.path)
            .map_err(|error| format!("could not replace {}: {error}", self.path.display()))?;
        Ok(())
    }
}

#[cfg(target_os = "macos")]
fn settings_from_macos_defaults() -> Option<Settings> {
    let domain = "com.davafons.timescale";
    let output = std::process::Command::new("/usr/bin/defaults")
        .args(["read", domain])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }

    let mut settings = Settings::default();
    if let Some(value) =
        macos_default(domain, "dayStartMinutes").and_then(|value| value.parse().ok())
    {
        settings.day.start = minutes_as_time(value);
    }
    if let Some(value) = macos_default(domain, "dayEndMinutes").and_then(|value| value.parse().ok())
    {
        settings.day.end = minutes_as_time(value);
    }
    if let Some(value) = macos_default(domain, "routineName")
        && !value.trim().is_empty()
    {
        settings.routine.name = value;
    }
    if let Some(value) = macos_integer(domain, "routineDurationMinutes") {
        settings.routine.duration_minutes = value.clamp(1, 10_080) as u32;
    }
    if let Some(value) = macos_number(domain, "routineStartedTimestamp")
        && value > 0.0
        && let LocalResult::Single(started_at) = Utc.timestamp_millis_opt((value * 1000.0) as i64)
    {
        settings.routine.started_at = Some(started_at.to_rfc3339());
    }
    if let Some(value) = macos_default(domain, "weekStartsOn") {
        settings.week.starts_on = if value == "sunday" {
            WeekStart::Sunday
        } else {
            WeekStart::Monday
        };
    }
    if let Some(value) = macos_default(domain, "quarterCycle") {
        settings.quarter.cycle = if value == "japanFiscal" {
            QuarterCycle::JapanFiscal
        } else {
            QuarterCycle::Calendar
        };
    }
    settings.solar.enabled = macos_bool(domain, "showSolarEvents").unwrap_or(true);
    if macos_bool(domain, "locationConfigured") == Some(true) {
        settings.solar.latitude = macos_number(domain, "latitude");
        settings.solar.longitude = macos_number(domain, "longitude");
    }
    if macos_bool(domain, "birthDateConfigured") == Some(true)
        && let (Some(year), Some(month), Some(day)) = (
            macos_integer(domain, "birthYear"),
            macos_integer(domain, "birthMonth"),
            macos_integer(domain, "birthDay"),
        )
    {
        settings.life.birth_date = Some(format!("{year:04}-{month:02}-{day:02}"));
    }
    if let Some(value) = macos_default(domain, "country") {
        settings.life.country = value;
    }
    if let Some(value) = macos_number(domain, "lifeExpectancy") {
        settings.life.expectancy_years = value;
    }
    settings.visible = Period::ALL
        .into_iter()
        .filter(|period| {
            let key = match period {
                Period::Day => "showDay",
                Period::Week => "showWeek",
                Period::Month => "showMonth",
                Period::Quarter => "showQuarter",
                Period::Year => "showYear",
                Period::Life => "showLife",
            };
            macos_bool(domain, key).unwrap_or(true)
        })
        .collect();
    if let Some(value) = macos_default(domain, "accent") {
        settings.mac_os.accent = value;
    }
    if let Some(value) = macos_integer(domain, "precision") {
        settings.mac_os.precision = value.clamp(0, 3) as u8;
    }
    settings.mac_os.show_remaining = macos_bool(domain, "showRemaining").unwrap_or(false);
    settings.validate().ok()?;
    Some(settings)
}

#[cfg(target_os = "macos")]
fn macos_default(domain: &str, key: &str) -> Option<String> {
    let output = std::process::Command::new("/usr/bin/defaults")
        .args(["read", domain, key])
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}

#[cfg(target_os = "macos")]
fn macos_bool(domain: &str, key: &str) -> Option<bool> {
    match macos_default(domain, key)?.to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" => Some(true),
        "0" | "false" | "no" => Some(false),
        _ => None,
    }
}

#[cfg(target_os = "macos")]
fn macos_number(domain: &str, key: &str) -> Option<f64> {
    macos_default(domain, key)?.trim_matches('"').parse().ok()
}

#[cfg(target_os = "macos")]
fn macos_integer(domain: &str, key: &str) -> Option<i32> {
    macos_default(domain, key)?.parse().ok()
}

#[cfg(target_os = "macos")]
fn minutes_as_time(minutes: u32) -> String {
    let minutes = minutes.min(23 * 60 + 59);
    format!("{:02}:{:02}", minutes / 60, minutes % 60)
}

pub fn config_path() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os("TIMESCALE_CONFIG") {
        return Ok(PathBuf::from(path));
    }
    let home = env::var_os("HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("USERPROFILE").map(PathBuf::from))
        .ok_or_else(|| "could not determine the home directory".to_string())?;
    #[cfg(target_os = "macos")]
    let directory = home.join("Library/Application Support/Timescale");
    #[cfg(all(not(target_os = "macos"), not(windows)))]
    let directory = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".config"))
        .join("timescale");
    #[cfg(windows)]
    let directory = env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join("AppData/Roaming"))
        .join("Timescale");
    Ok(directory.join("config.json"))
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub generated_at: String,
    pub routine: Option<RoutineProgress>,
    pub rows: Vec<ProgressRow>,
    pub solar: Option<SolarEvents>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoutineProgress {
    pub name: String,
    pub elapsed: f64,
    pub remaining_seconds: f64,
    pub duration_seconds: f64,
    pub started_at: String,
    pub ends_at: String,
    pub complete: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgressRow {
    pub period: Period,
    pub title: String,
    pub detail: Option<String>,
    pub elapsed: f64,
    pub remaining_seconds: f64,
    pub one_percent_seconds: f64,
    pub start: String,
    pub end: String,
    pub marker: Option<f64>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SolarEvents {
    pub sunrise: String,
    pub sunset: String,
    pub sunrise_fraction: f64,
    pub sunset_fraction: f64,
}

#[derive(Debug, Clone)]
struct Interval {
    start: DateTime<Local>,
    end: DateTime<Local>,
}

impl Interval {
    fn elapsed(&self, now: DateTime<Local>) -> f64 {
        fraction(now, self.start, self.end)
    }

    fn duration_seconds(&self) -> f64 {
        (self.end - self.start).num_milliseconds() as f64 / 1000.0
    }
}

pub fn snapshot(settings: &Settings, now: DateTime<Local>) -> Result<Snapshot, String> {
    settings.validate()?;
    let mut rows = Vec::new();
    let day = active_day(
        now,
        parse_time(&settings.day.start)?,
        parse_time(&settings.day.end)?,
    );

    for period in &settings.visible {
        let row = match period {
            Period::Day => row_for_interval(Period::Day, "Day".into(), None, &day, now, None),
            Period::Week => {
                let interval = week_interval(now, &settings.week.starts_on);
                row_for_interval(
                    Period::Week,
                    format!("Week {}", week_number(now, &settings.week.starts_on)),
                    None,
                    &interval,
                    now,
                    None,
                )
            }
            Period::Month => {
                let interval = month_interval(now);
                row_for_interval(
                    Period::Month,
                    now.format("%B").to_string(),
                    None,
                    &interval,
                    now,
                    None,
                )
            }
            Period::Quarter => {
                let (interval, number) =
                    quarter_interval(now, settings.quarter.cycle.start_month());
                let prefix = if settings.quarter.cycle == QuarterCycle::Calendar {
                    "Quarter"
                } else {
                    "Fiscal"
                };
                row_for_interval(
                    Period::Quarter,
                    format!("{prefix} Q{number}"),
                    Some(format!(
                        "{} – {}",
                        interval.start.format("%b %-d"),
                        (interval.end - Duration::days(1)).format("%b %-d")
                    )),
                    &interval,
                    now,
                    None,
                )
            }
            Period::Year => {
                let interval = year_interval(now);
                let marker = settings.life.birth_date.as_deref().and_then(|birth| {
                    birthday_in_year(birth, now.year())
                        .map(|date| date_at(date, 12 * 60))
                        .map(|date| fraction(date, interval.start, interval.end))
                });
                row_for_interval(
                    Period::Year,
                    format!("Year {}", now.year()),
                    None,
                    &interval,
                    now,
                    marker,
                )
            }
            Period::Life => life_row(settings, now)?,
        };
        rows.push(row);
    }

    let solar = if settings.solar.enabled {
        match (settings.solar.latitude, settings.solar.longitude) {
            (Some(latitude), Some(longitude)) => {
                solar_events_for_interval(&day, latitude, longitude).map(|(sunrise, sunset)| {
                    SolarEvents {
                        sunrise: sunrise.to_rfc3339(),
                        sunset: sunset.to_rfc3339(),
                        sunrise_fraction: fraction(sunrise, day.start, day.end),
                        sunset_fraction: fraction(sunset, day.start, day.end),
                    }
                })
            }
            _ => None,
        }
    } else {
        None
    };

    let routine = settings
        .routine
        .started_at
        .as_deref()
        .map(|started_at| -> Result<RoutineProgress, String> {
            let start = DateTime::parse_from_rfc3339(started_at)
                .map_err(|_| "routine.startedAt must be an RFC 3339 timestamp".to_string())?
                .with_timezone(&Local);
            let end = start + Duration::minutes(i64::from(settings.routine.duration_minutes));
            let duration_seconds = f64::from(settings.routine.duration_minutes) * 60.0;
            let elapsed = fraction(now, start, end);
            Ok(RoutineProgress {
                name: settings.routine.name.clone(),
                elapsed,
                remaining_seconds: (end - now).num_milliseconds().max(0) as f64 / 1000.0,
                duration_seconds,
                started_at: start.to_rfc3339(),
                ends_at: end.to_rfc3339(),
                complete: now >= end,
            })
        })
        .transpose()?;

    Ok(Snapshot {
        generated_at: now.to_rfc3339(),
        routine,
        rows,
        solar,
    })
}

fn row_for_interval(
    period: Period,
    title: String,
    detail: Option<String>,
    interval: &Interval,
    now: DateTime<Local>,
    marker: Option<f64>,
) -> ProgressRow {
    let elapsed = interval.elapsed(now);
    let duration = interval.duration_seconds();
    ProgressRow {
        period,
        title,
        detail,
        elapsed,
        remaining_seconds: (duration * (1.0 - elapsed)).max(0.0),
        one_percent_seconds: duration / 100.0,
        start: interval.start.to_rfc3339(),
        end: interval.end.to_rfc3339(),
        marker,
    }
}

fn active_day(now: DateTime<Local>, start_minutes: u32, end_minutes: u32) -> Interval {
    let date = now.date_naive();
    let minute = now.hour() * 60 + now.minute();
    if start_minutes < end_minutes {
        return Interval {
            start: date_at(date, start_minutes),
            end: date_at(date, end_minutes),
        };
    }
    if minute >= start_minutes {
        Interval {
            start: date_at(date, start_minutes),
            end: date_at(date.succ_opt().expect("next date"), end_minutes),
        }
    } else {
        Interval {
            start: date_at(date.pred_opt().expect("previous date"), start_minutes),
            end: date_at(date, end_minutes),
        }
    }
}

fn week_interval(now: DateTime<Local>, starts_on: &WeekStart) -> Interval {
    let offset = match starts_on {
        WeekStart::Monday => now.weekday().num_days_from_monday(),
        WeekStart::Sunday => now.weekday().num_days_from_sunday(),
    } as i64;
    let date = now.date_naive() - Duration::days(offset);
    Interval {
        start: date_at(date, 0),
        end: date_at(date + Duration::days(7), 0),
    }
}

fn week_number(now: DateTime<Local>, starts_on: &WeekStart) -> u32 {
    match starts_on {
        WeekStart::Monday => now.iso_week().week(),
        WeekStart::Sunday => {
            let january_first =
                NaiveDate::from_ymd_opt(now.year(), 1, 1).expect("valid first day of year");
            let first_week_start = january_first
                - Duration::days(january_first.weekday().num_days_from_sunday() as i64);
            ((now.date_naive() - first_week_start).num_days() / 7 + 1) as u32
        }
    }
}

fn month_interval(now: DateTime<Local>) -> Interval {
    let date = NaiveDate::from_ymd_opt(now.year(), now.month(), 1).expect("valid month");
    Interval {
        start: date_at(date, 0),
        end: date_at(add_months(date, 1), 0),
    }
}

fn quarter_interval(now: DateTime<Local>, start_month: u32) -> (Interval, u32) {
    let offset = (now.month() + 12 - start_month) % 12;
    let number = offset / 3 + 1;
    let months_back = offset % 3;
    let current_month = NaiveDate::from_ymd_opt(now.year(), now.month(), 1).expect("valid month");
    let start_date = add_months(current_month, -(months_back as i32));
    (
        Interval {
            start: date_at(start_date, 0),
            end: date_at(add_months(start_date, 3), 0),
        },
        number,
    )
}

fn year_interval(now: DateTime<Local>) -> Interval {
    Interval {
        start: date_at(
            NaiveDate::from_ymd_opt(now.year(), 1, 1).expect("valid year"),
            0,
        ),
        end: date_at(
            NaiveDate::from_ymd_opt(now.year() + 1, 1, 1).expect("valid next year"),
            0,
        ),
    }
}

fn life_row(settings: &Settings, now: DateTime<Local>) -> Result<ProgressRow, String> {
    let Some(raw_birth_date) = settings.life.birth_date.as_deref() else {
        return Ok(ProgressRow {
            period: Period::Life,
            title: "Life".into(),
            detail: Some("Not configured".into()),
            elapsed: 0.0,
            remaining_seconds: 0.0,
            one_percent_seconds: 0.0,
            start: String::new(),
            end: String::new(),
            marker: None,
        });
    };
    let birth_date = NaiveDate::parse_from_str(raw_birth_date, "%Y-%m-%d")
        .map_err(|_| "life.birthDate must use YYYY-MM-DD".to_string())?;
    let start = date_at(birth_date, 12 * 60);
    let whole_years = settings.life.expectancy_years.floor() as i32;
    let whole_year_end = clamped_date(
        birth_date.year() + whole_years,
        birth_date.month(),
        birth_date.day(),
    );
    let partial_days = ((settings.life.expectancy_years - whole_years as f64) * 365.2425).round();
    let end = date_at(
        whole_year_end + Duration::days(partial_days as i64),
        12 * 60,
    );
    let interval = Interval { start, end };
    let age = decimal_age(birth_date, now);
    Ok(row_for_interval(
        Period::Life,
        "Life".into(),
        Some(format!(
            "Age {age:.1} / {:.1}",
            settings.life.expectancy_years
        )),
        &interval,
        now,
        None,
    ))
}

fn decimal_age(birth_date: NaiveDate, now: DateTime<Local>) -> f64 {
    if now.date_naive() < birth_date {
        return 0.0;
    }
    let mut years = now.year() - birth_date.year();
    let birthday = clamped_date(now.year(), birth_date.month(), birth_date.day());
    if now.date_naive() < birthday {
        years -= 1;
    }
    let previous = clamped_date(
        birth_date.year() + years,
        birth_date.month(),
        birth_date.day(),
    );
    let next = clamped_date(
        birth_date.year() + years + 1,
        birth_date.month(),
        birth_date.day(),
    );
    let within = (now.date_naive() - previous).num_days() as f64;
    let length = (next - previous).num_days() as f64;
    years as f64 + within / length
}

fn birthday_in_year(raw_birth_date: &str, year: i32) -> Option<NaiveDate> {
    let birth = NaiveDate::parse_from_str(raw_birth_date, "%Y-%m-%d").ok()?;
    Some(clamped_date(year, birth.month(), birth.day()))
}

fn clamped_date(year: i32, month: u32, day: u32) -> NaiveDate {
    (1..=day)
        .rev()
        .find_map(|candidate| NaiveDate::from_ymd_opt(year, month, candidate))
        .expect("month has at least one day")
}

fn add_months(date: NaiveDate, months: i32) -> NaiveDate {
    let index = date.year() * 12 + date.month0() as i32 + months;
    let year = index.div_euclid(12);
    let month = index.rem_euclid(12) as u32 + 1;
    clamped_date(year, month, date.day())
}

fn parse_time(value: &str) -> Result<u32, String> {
    let (hour_text, minute_text) = value
        .split_once(':')
        .ok_or_else(|| format!("invalid time {value:?}; expected HH:MM"))?;
    let hour: u32 = hour_text
        .parse()
        .map_err(|_| format!("invalid hour in {value:?}"))?;
    let minute: u32 = minute_text
        .parse()
        .map_err(|_| format!("invalid minute in {value:?}"))?;
    if hour > 23 || minute > 59 || hour_text.len() != 2 || minute_text.len() != 2 {
        return Err(format!("invalid time {value:?}; expected HH:MM"));
    }
    Ok(hour * 60 + minute)
}

fn date_at(date: NaiveDate, minutes: u32) -> DateTime<Local> {
    let mut candidate = date
        .and_hms_opt(minutes / 60, minutes % 60, 0)
        .expect("validated wall time");
    for _ in 0..=180 {
        match Local.from_local_datetime(&candidate) {
            LocalResult::Single(value) | LocalResult::Ambiguous(value, _) => return value,
            LocalResult::None => candidate += Duration::minutes(1),
        }
    }
    Local.from_utc_datetime(&candidate)
}

fn fraction(now: DateTime<Local>, start: DateTime<Local>, end: DateTime<Local>) -> f64 {
    let duration = (end - start).num_milliseconds() as f64;
    if duration <= 0.0 {
        return 0.0;
    }
    (((now - start).num_milliseconds() as f64) / duration).clamp(0.0, 1.0)
}

fn solar_events_for_interval(
    interval: &Interval,
    latitude: f64,
    longitude: f64,
) -> Option<(DateTime<Local>, DateTime<Local>)> {
    let final_moment = interval.end - Duration::milliseconds(1);
    [interval.start.date_naive(), final_moment.date_naive()]
        .into_iter()
        .filter_map(|date| solar_events(date, latitude, longitude))
        .max_by_key(|(sunrise, sunset)| {
            let overlap_start = (*sunrise).max(interval.start);
            let overlap_end = (*sunset).min(interval.end);
            (overlap_end - overlap_start).num_milliseconds().max(0)
        })
}

fn solar_events(
    date: NaiveDate,
    latitude: f64,
    longitude: f64,
) -> Option<(DateTime<Local>, DateTime<Local>)> {
    let sunrise = universal_hour(date.ordinal(), latitude, longitude, true)?;
    let sunset = universal_hour(date.ordinal(), latitude, longitude, false)?;
    Some((
        utc_hour_on_local_date(date, sunrise)?,
        utc_hour_on_local_date(date, sunset)?,
    ))
}

fn universal_hour(day: u32, latitude: f64, longitude: f64, sunrise: bool) -> Option<f64> {
    let longitude_hour = longitude / 15.0;
    let approximate = day as f64 + ((if sunrise { 6.0 } else { 18.0 }) - longitude_hour) / 24.0;
    let anomaly = 0.9856 * approximate - 3.289;
    let mut true_longitude =
        anomaly + 1.916 * sin_degrees(anomaly) + 0.020 * sin_degrees(2.0 * anomaly) + 282.634;
    true_longitude = normalize(true_longitude, 360.0);
    let mut right_ascension = (0.91764 * tan_degrees(true_longitude)).atan().to_degrees();
    right_ascension +=
        (true_longitude / 90.0).floor() * 90.0 - (right_ascension / 90.0).floor() * 90.0;
    right_ascension /= 15.0;
    let sin_declination = 0.39782 * sin_degrees(true_longitude);
    let cos_declination = sin_declination.asin().cos();
    let cos_hour = (cos_degrees(90.833) - sin_declination * sin_degrees(latitude))
        / (cos_declination * cos_degrees(latitude));
    if !(-1.0..=1.0).contains(&cos_hour) {
        return None;
    }
    let angle = if sunrise {
        360.0 - cos_hour.acos().to_degrees()
    } else {
        cos_hour.acos().to_degrees()
    } / 15.0;
    let local_mean = angle + right_ascension - 0.06571 * approximate - 6.622;
    Some(normalize(local_mean - longitude_hour, 24.0))
}

fn utc_hour_on_local_date(date: NaiveDate, hour: f64) -> Option<DateTime<Local>> {
    let base = Utc
        .with_ymd_and_hms(date.year(), date.month(), date.day(), 0, 0, 0)
        .single()?;
    let candidate = base + Duration::milliseconds((hour * 3_600_000.0).round() as i64);
    [-1, 0, 1]
        .into_iter()
        .map(|offset| (candidate + Duration::days(offset)).with_timezone(&Local))
        .find(|value| value.date_naive() == date)
}

fn normalize(value: f64, maximum: f64) -> f64 {
    value.rem_euclid(maximum)
}

fn sin_degrees(value: f64) -> f64 {
    value.to_radians().sin()
}

fn cos_degrees(value: f64) -> f64 {
    value.to_radians().cos()
}

fn tan_degrees(value: f64) -> f64 {
    value.to_radians().tan()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_configuration_round_trips() {
        let expected = Settings::default();
        let encoded = serde_json::to_vec(&expected).unwrap();
        let decoded: Settings = serde_json::from_slice(&encoded).unwrap();
        assert_eq!(decoded, expected);
    }

    #[test]
    fn shared_example_matches_rust_model() {
        let settings: Settings =
            serde_json::from_str(include_str!("../../../config/example.json")).unwrap();
        settings.validate().unwrap();
        assert_eq!(settings.tui.motion, TuiMotion::Full);
    }

    #[test]
    fn configuration_rejects_duplicates_and_unknown_accents() {
        let duplicates = Settings {
            visible: vec![Period::Day, Period::Day],
            ..Settings::default()
        };
        assert!(duplicates.validate().is_err());

        let accent = Settings {
            mac_os: MacOsSettings {
                accent: "chartreuse".into(),
                ..MacOsSettings::default()
            },
            ..Settings::default()
        };
        assert!(accent.validate().is_err());
    }

    #[test]
    fn midday_is_half_of_a_calendar_day() {
        let now = Local
            .with_ymd_and_hms(2026, 9, 5, 12, 0, 0)
            .single()
            .unwrap();
        let interval = active_day(now, 0, 1_439);
        assert!((interval.elapsed(now) - 0.5003).abs() < 0.001);
    }

    #[test]
    fn routine_progress_uses_its_saved_start_and_duration() {
        let now = Local
            .with_ymd_and_hms(2026, 9, 6, 10, 0, 0)
            .single()
            .unwrap();
        let mut settings = Settings::default();
        settings.routine.duration_minutes = 8 * 60;
        settings.routine.started_at = Some((now - Duration::hours(2)).to_rfc3339());

        let routine = snapshot(&settings, now).unwrap().routine.unwrap();
        assert!((routine.elapsed - 0.25).abs() < 0.0001);
        assert_eq!(routine.remaining_seconds, 6.0 * 60.0 * 60.0);
        assert!(!routine.complete);
    }

    #[test]
    fn japan_fiscal_quarter_starts_in_april() {
        let now = Local
            .with_ymd_and_hms(2026, 5, 1, 0, 0, 0)
            .single()
            .unwrap();
        let (interval, number) = quarter_interval(now, 4);
        assert_eq!(number, 1);
        assert_eq!(interval.start.month(), 4);
        assert_eq!(interval.end.month(), 7);
    }

    #[test]
    fn tokyo_solar_events_match_requested_date() {
        let date = NaiveDate::from_ymd_opt(2026, 9, 5).unwrap();
        let (sunrise, sunset) = solar_events(date, 35.6762, 139.6503).unwrap();
        assert_eq!(sunrise.date_naive(), date);
        assert_eq!(sunset.date_naive(), date);
        assert!(sunrise < sunset);
    }

    #[test]
    fn solar_events_follow_the_active_waking_day_after_midnight() {
        let mut settings = Settings::default();
        settings.day.start = "08:00".into();
        settings.day.end = "00:00".into();
        settings.solar.latitude = Some(35.6762);
        settings.solar.longitude = Some(139.6503);
        let now = Local
            .with_ymd_and_hms(2026, 9, 6, 0, 15, 0)
            .single()
            .unwrap();

        let value = snapshot(&settings, now).unwrap();
        let solar = value.solar.unwrap();
        let sunrise = DateTime::parse_from_rfc3339(&solar.sunrise).unwrap();

        assert_eq!(
            sunrise.date_naive(),
            NaiveDate::from_ymd_opt(2026, 9, 5).unwrap()
        );
        assert_eq!(solar.sunrise_fraction, 0.0);
        assert!(solar.sunset_fraction > 0.6 && solar.sunset_fraction < 0.7);
    }
}
