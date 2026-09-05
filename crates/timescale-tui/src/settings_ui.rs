use crossterm::event::{KeyCode, KeyEvent};
use ratatui::Frame;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, Clear, Padding, Paragraph};
use timescale_core::{ConfigStore, Period, QuarterCycle, Settings, TuiMotion, TuiTheme, WeekStart};

use super::ThemePalette;

#[cfg(target_os = "macos")]
use std::process::Command;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Field {
    DayStart,
    DayEnd,
    RoutineName,
    RoutineDuration,
    WeekStart,
    QuarterCycle,
    SolarEnabled,
    SolarLocation,
    BirthDate,
    Country,
    Expectancy,
    Visible(Period),
    MacAccent,
    Precision,
    ShowRemaining,
    Theme,
    Motion,
}

#[derive(Clone, Copy)]
struct FieldSpec {
    section: &'static str,
    label: &'static str,
    field: Field,
}

const FIELDS: [FieldSpec; 22] = [
    FieldSpec {
        section: "VISIBLE PROGRESS",
        label: "Day",
        field: Field::Visible(Period::Day),
    },
    FieldSpec {
        section: "VISIBLE PROGRESS",
        label: "Week",
        field: Field::Visible(Period::Week),
    },
    FieldSpec {
        section: "VISIBLE PROGRESS",
        label: "Week starts on",
        field: Field::WeekStart,
    },
    FieldSpec {
        section: "VISIBLE PROGRESS",
        label: "Month",
        field: Field::Visible(Period::Month),
    },
    FieldSpec {
        section: "VISIBLE PROGRESS",
        label: "Quarter",
        field: Field::Visible(Period::Quarter),
    },
    FieldSpec {
        section: "VISIBLE PROGRESS",
        label: "Quarter cycle",
        field: Field::QuarterCycle,
    },
    FieldSpec {
        section: "VISIBLE PROGRESS",
        label: "Year",
        field: Field::Visible(Period::Year),
    },
    FieldSpec {
        section: "VISIBLE PROGRESS",
        label: "Life estimate",
        field: Field::Visible(Period::Life),
    },
    FieldSpec {
        section: "WAKING DAY",
        label: "Starts",
        field: Field::DayStart,
    },
    FieldSpec {
        section: "WAKING DAY",
        label: "Ends",
        field: Field::DayEnd,
    },
    FieldSpec {
        section: "ROUTINE",
        label: "Name",
        field: Field::RoutineName,
    },
    FieldSpec {
        section: "ROUTINE",
        label: "Duration",
        field: Field::RoutineDuration,
    },
    FieldSpec {
        section: "SUN",
        label: "Show sunrise and sunset",
        field: Field::SolarEnabled,
    },
    FieldSpec {
        section: "SUN",
        label: "Location",
        field: Field::SolarLocation,
    },
    FieldSpec {
        section: "LIFE ESTIMATE",
        label: "Birth date",
        field: Field::BirthDate,
    },
    FieldSpec {
        section: "LIFE ESTIMATE",
        label: "Country",
        field: Field::Country,
    },
    FieldSpec {
        section: "LIFE ESTIMATE",
        label: "Life expectancy",
        field: Field::Expectancy,
    },
    FieldSpec {
        section: "APPEARANCE",
        label: "Display",
        field: Field::ShowRemaining,
    },
    FieldSpec {
        section: "APPEARANCE",
        label: "Decimal places",
        field: Field::Precision,
    },
    FieldSpec {
        section: "APPEARANCE",
        label: "Accent",
        field: Field::MacAccent,
    },
    FieldSpec {
        section: "TERMINAL",
        label: "Theme",
        field: Field::Theme,
    },
    FieldSpec {
        section: "TERMINAL",
        label: "Motion",
        field: Field::Motion,
    },
];

struct EditState {
    field: Field,
    value: String,
    cursor: usize,
}

struct PickerState {
    field: Field,
    query: String,
    selected: usize,
}

#[derive(Clone, Copy)]
struct Choice {
    label: &'static str,
    value: &'static str,
    expectancy: Option<f64>,
}

const WEEK_CHOICES: [Choice; 2] = [
    Choice::new("Monday", "monday"),
    Choice::new("Sunday", "sunday"),
];
const QUARTER_CHOICES: [Choice; 2] = [
    Choice::new("Calendar", "calendar"),
    Choice::new("Japan fiscal", "japanFiscal"),
];
const ACCENT_CHOICES: [Choice; 6] = [
    Choice::new("System", "system"),
    Choice::new("Orange", "orange"),
    Choice::new("Blue", "blue"),
    Choice::new("Green", "green"),
    Choice::new("Purple", "purple"),
    Choice::new("Monochrome", "monochrome"),
];
const DISPLAY_CHOICES: [Choice; 2] = [
    Choice::new("Elapsed", "elapsed"),
    Choice::new("Remaining", "remaining"),
];
const PRECISION_CHOICES: [Choice; 4] = [
    Choice::new("0", "0"),
    Choice::new("1", "1"),
    Choice::new("2", "2"),
    Choice::new("3", "3"),
];
const THEME_CHOICES: [Choice; 6] = [
    Choice::new("Auto", "auto"),
    Choice::new("Color", "color"),
    Choice::new("Catppuccin", "catppuccin"),
    Choice::new("Tokyo Night", "tokyoNight"),
    Choice::new("Gruvbox", "gruvbox"),
    Choice::new("Monochrome", "monochrome"),
];
const MOTION_CHOICES: [Choice; 3] = [
    Choice::new("Full", "full"),
    Choice::new("Reduced", "reduced"),
    Choice::new("Off", "off"),
];
const COUNTRY_CHOICES: [Choice; 10] = [
    Choice::country("Australia", 83.0),
    Choice::country("Canada", 82.0),
    Choice::country("France", 83.0),
    Choice::country("Germany", 81.0),
    Choice::country("Italy", 84.0),
    Choice::country("Japan", 84.0),
    Choice::country("Spain", 84.0),
    Choice::country("Switzerland", 84.0),
    Choice::country("United Kingdom", 81.0),
    Choice::country("United States", 79.0),
];

impl Choice {
    const fn new(label: &'static str, value: &'static str) -> Self {
        Self {
            label,
            value,
            expectancy: None,
        }
    }

    const fn country(label: &'static str, expectancy: f64) -> Self {
        Self {
            label,
            value: label,
            expectancy: Some(expectancy),
        }
    }
}

pub struct SettingsMenu {
    selected: usize,
    editing: Option<EditState>,
    picker: Option<PickerState>,
    notice: Option<(String, bool)>,
}

pub enum MenuAction {
    Stay,
    Close,
    Quit,
}

impl SettingsMenu {
    pub fn new() -> Self {
        Self {
            selected: 0,
            editing: None,
            picker: None,
            notice: None,
        }
    }

    pub fn handle_key(
        &mut self,
        key: KeyEvent,
        settings: &mut Settings,
        store: &ConfigStore,
    ) -> MenuAction {
        if self.editing.is_some() {
            return self.handle_edit_key(key, settings, store);
        }
        if self.picker.is_some() {
            return self.handle_picker_key(key, settings, store);
        }
        match key.code {
            KeyCode::Esc | KeyCode::Char('e') => MenuAction::Close,
            KeyCode::Char('q') => MenuAction::Quit,
            KeyCode::Up | KeyCode::Char('k') => {
                self.selected = self.selected.saturating_sub(1);
                self.notice = None;
                MenuAction::Stay
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.selected = (self.selected + 1).min(FIELDS.len() - 1);
                self.notice = None;
                MenuAction::Stay
            }
            KeyCode::Home => {
                self.selected = 0;
                self.notice = None;
                MenuAction::Stay
            }
            KeyCode::End => {
                self.selected = FIELDS.len() - 1;
                self.notice = None;
                MenuAction::Stay
            }
            KeyCode::PageUp => {
                self.selected = self.selected.saturating_sub(6);
                self.notice = None;
                MenuAction::Stay
            }
            KeyCode::PageDown => {
                self.selected = (self.selected + 6).min(FIELDS.len() - 1);
                self.notice = None;
                MenuAction::Stay
            }
            KeyCode::Left => {
                self.change_selected(settings, store, -1);
                MenuAction::Stay
            }
            KeyCode::Right | KeyCode::Char(' ') => {
                self.change_selected(settings, store, 1);
                MenuAction::Stay
            }
            KeyCode::Char('g') if FIELDS[self.selected].field == Field::SolarLocation => {
                self.notice = Some(match request_current_location() {
                    Ok(()) => (
                        "Location requested from the Timescale Mac app".into(),
                        false,
                    ),
                    Err(error) => (error, true),
                });
                MenuAction::Stay
            }
            KeyCode::Enter => {
                let field = FIELDS[self.selected].field;
                if choices(field).is_some() {
                    self.open_picker(field, settings);
                } else if is_text_field(field) {
                    let value = editable_value(field, settings);
                    self.editing = Some(EditState {
                        cursor: value.chars().count(),
                        field,
                        value,
                    });
                    self.notice = None;
                } else {
                    self.change_selected(settings, store, 1);
                }
                MenuAction::Stay
            }
            _ => MenuAction::Stay,
        }
    }

    fn open_picker(&mut self, field: Field, settings: &Settings) {
        let current = choice_value(field, settings);
        let selected = choices(field)
            .and_then(|items| items.iter().position(|item| item.value == current))
            .unwrap_or(0);
        self.picker = Some(PickerState {
            field,
            query: String::new(),
            selected,
        });
        self.notice = None;
    }

    fn handle_picker_key(
        &mut self,
        key: KeyEvent,
        settings: &mut Settings,
        store: &ConfigStore,
    ) -> MenuAction {
        match key.code {
            KeyCode::Esc => {
                self.picker = None;
                self.notice = Some(("Selection cancelled".into(), false));
            }
            KeyCode::Up => {
                if let Some(picker) = self.picker.as_mut() {
                    picker.selected = picker.selected.saturating_sub(1);
                }
            }
            KeyCode::Down => {
                if let Some(picker) = self.picker.as_mut() {
                    let count = matching_choices(picker).len();
                    picker.selected = (picker.selected + 1).min(count.saturating_sub(1));
                }
            }
            KeyCode::Home => {
                if let Some(picker) = self.picker.as_mut() {
                    picker.selected = 0;
                }
            }
            KeyCode::End => {
                if let Some(picker) = self.picker.as_mut() {
                    picker.selected = matching_choices(picker).len().saturating_sub(1);
                }
            }
            KeyCode::Backspace => {
                if let Some(picker) = self.picker.as_mut() {
                    picker.query.pop();
                    picker.selected = 0;
                }
            }
            KeyCode::Char(character) => {
                if let Some(picker) = self.picker.as_mut() {
                    picker.query.push(character);
                    picker.selected = 0;
                }
            }
            KeyCode::Enter => {
                let selection = self.picker.as_ref().and_then(|picker| {
                    matching_choices(picker)
                        .get(picker.selected)
                        .copied()
                        .map(|choice| (picker.field, choice))
                });
                if let Some((field, choice)) = selection {
                    let mut candidate = settings.clone();
                    let result = apply_choice(field, choice, &mut candidate)
                        .and_then(|()| store.save(&candidate));
                    match result {
                        Ok(()) => {
                            *settings = candidate;
                            self.picker = None;
                            self.notice = Some(("Saved".into(), false));
                        }
                        Err(error) => self.notice = Some((error, true)),
                    }
                } else {
                    self.notice = Some(("No matching option".into(), true));
                }
            }
            _ => {}
        }
        MenuAction::Stay
    }

    fn handle_edit_key(
        &mut self,
        key: KeyEvent,
        settings: &mut Settings,
        store: &ConfigStore,
    ) -> MenuAction {
        let edit = self.editing.as_mut().expect("editing checked");
        match key.code {
            KeyCode::Esc => {
                self.editing = None;
                self.notice = Some(("Edit cancelled".into(), false));
            }
            KeyCode::Enter => {
                let field = edit.field;
                let value = edit.value.clone();
                match save_text_value(field, &value, settings, store) {
                    Ok(()) => {
                        self.editing = None;
                        self.notice = Some(("Saved".into(), false));
                    }
                    Err(error) => self.notice = Some((error, true)),
                }
            }
            KeyCode::Left => edit.cursor = edit.cursor.saturating_sub(1),
            KeyCode::Right => edit.cursor = (edit.cursor + 1).min(edit.value.chars().count()),
            KeyCode::Home => edit.cursor = 0,
            KeyCode::End => edit.cursor = edit.value.chars().count(),
            KeyCode::Backspace if edit.cursor > 0 => {
                let start = char_byte_index(&edit.value, edit.cursor - 1);
                let end = char_byte_index(&edit.value, edit.cursor);
                edit.value.replace_range(start..end, "");
                edit.cursor -= 1;
            }
            KeyCode::Delete if edit.cursor < edit.value.chars().count() => {
                let start = char_byte_index(&edit.value, edit.cursor);
                let end = char_byte_index(&edit.value, edit.cursor + 1);
                edit.value.replace_range(start..end, "");
            }
            KeyCode::Char(character) => {
                let index = char_byte_index(&edit.value, edit.cursor);
                edit.value.insert(index, character);
                edit.cursor += 1;
            }
            _ => {}
        }
        MenuAction::Stay
    }

    fn change_selected(&mut self, settings: &mut Settings, store: &ConfigStore, direction: i8) {
        let field = FIELDS[self.selected].field;
        if matches!(
            field,
            Field::RoutineName | Field::SolarLocation | Field::BirthDate
        ) {
            self.notice = Some(("Press Enter to edit".into(), false));
            return;
        }
        let mut candidate = settings.clone();
        let result =
            change_field(field, &mut candidate, direction).and_then(|()| store.save(&candidate));
        match result {
            Ok(()) => {
                *settings = candidate;
                self.notice = Some(("Saved".into(), false));
            }
            Err(error) => self.notice = Some((error, true)),
        }
    }

    pub fn draw(&self, frame: &mut Frame<'_>, settings: &Settings, palette: ThemePalette) {
        let area = frame.area();
        let block = Block::default()
            .title(" settings ")
            .borders(Borders::ALL)
            .padding(Padding::new(2, 2, 2, 2));
        let inner = block.inner(area);
        frame.render_widget(block, area);
        let [header, body, footer] = Layout::vertical([
            Constraint::Length(3),
            Constraint::Min(1),
            Constraint::Length(2),
        ])
        .areas(inner);

        frame.render_widget(
            Paragraph::new(vec![
                Line::from(Span::styled(
                    "Timescale settings",
                    Style::default()
                        .fg(palette.primary)
                        .add_modifier(Modifier::BOLD),
                )),
                Line::from(Span::styled(
                    "Changes validate and save immediately",
                    Style::default().fg(palette.muted),
                )),
            ]),
            header,
        );

        let rows = menu_rows(settings, self, palette);
        let selected_row = rows
            .iter()
            .position(|row| row.field_index == Some(self.selected))
            .unwrap_or(0);
        let height = body.height as usize;
        let start = scroll_start(selected_row, height, rows.len());
        let lines = rows
            .into_iter()
            .skip(start)
            .take(height)
            .map(|row| row.line)
            .collect::<Vec<_>>();
        frame.render_widget(Paragraph::new(Text::from(lines)), body);

        let help = if self.picker.is_some() {
            "Type to filter · ↑↓ choose · Enter save · Esc cancel".into()
        } else if let Some(edit) = &self.editing {
            format!(
                "Enter save · Esc cancel · ←→ cursor · {}",
                edit_hint(edit.field)
            )
        } else if FIELDS[self.selected].field == Field::SolarLocation {
            "g current location · Enter coordinates · ←→ no change · Esc back".into()
        } else {
            "↑↓ navigate · ←→/Space change · Enter edit · Esc back".into()
        };
        let status = self.notice.as_ref().map_or_else(
            || format!("{} / {}", self.selected + 1, FIELDS.len()),
            |(message, _)| message.clone(),
        );
        let status_style = if self.notice.as_ref().is_some_and(|(_, error)| *error) {
            Style::default().fg(Color::Red)
        } else {
            Style::default().fg(palette.muted)
        };
        frame.render_widget(
            Paragraph::new(vec![
                Line::from(Span::styled(help, Style::default().fg(palette.muted))),
                Line::from(Span::styled(status, status_style)),
            ]),
            footer,
        );

        if let Some(picker) = &self.picker {
            draw_picker(frame, picker, palette);
        }
    }
}

struct MenuRow<'a> {
    field_index: Option<usize>,
    line: Line<'a>,
}

fn scroll_start(selected_row: usize, viewport_height: usize, row_count: usize) -> usize {
    selected_row
        .saturating_sub(viewport_height.saturating_sub(1) / 2)
        .min(row_count.saturating_sub(viewport_height))
}

fn draw_picker(frame: &mut Frame<'_>, picker: &PickerState, palette: ThemePalette) {
    let area = frame.area();
    let width = area.width.saturating_sub(4).min(52);
    let height = area.height.saturating_sub(2).min(16);
    if width < 12 || height < 6 {
        return;
    }
    let popup = Rect::new(
        area.x + (area.width - width) / 2,
        area.y + (area.height - height) / 2,
        width,
        height,
    );
    let block = Block::default()
        .title(format!(" select {} ", field_label(picker.field)))
        .borders(Borders::ALL)
        .padding(Padding::uniform(1));
    let inner = block.inner(popup);
    frame.render_widget(Clear, popup);
    frame.render_widget(block, popup);

    let options = matching_choices(picker);
    let list_height = inner.height.saturating_sub(2) as usize;
    let start = scroll_start(picker.selected, list_height, options.len());
    let mut lines = vec![
        Line::from(vec![
            Span::styled("Filter: ", Style::default().fg(palette.muted)),
            Span::styled(
                if picker.query.is_empty() {
                    "all"
                } else {
                    &picker.query
                },
                Style::default().fg(palette.primary),
            ),
        ]),
        Line::default(),
    ];
    if options.is_empty() {
        lines.push(Line::from(Span::styled(
            "No matching options",
            Style::default().fg(Color::Red),
        )));
    } else {
        lines.extend(
            options
                .iter()
                .enumerate()
                .skip(start)
                .take(list_height)
                .map(|(index, choice)| {
                    let selected = index == picker.selected;
                    Line::from(vec![
                        Span::styled(
                            if selected { "› " } else { "  " },
                            Style::default().fg(palette.accent),
                        ),
                        Span::styled(
                            choice.label,
                            if selected {
                                Style::default()
                                    .fg(palette.primary)
                                    .add_modifier(Modifier::BOLD)
                            } else {
                                Style::default().fg(palette.muted)
                            },
                        ),
                    ])
                }),
        );
    }
    frame.render_widget(Paragraph::new(lines), inner);
}

fn choices(field: Field) -> Option<&'static [Choice]> {
    match field {
        Field::WeekStart => Some(&WEEK_CHOICES),
        Field::QuarterCycle => Some(&QUARTER_CHOICES),
        Field::Country => Some(&COUNTRY_CHOICES),
        Field::ShowRemaining => Some(&DISPLAY_CHOICES),
        Field::Precision => Some(&PRECISION_CHOICES),
        Field::MacAccent => Some(&ACCENT_CHOICES),
        Field::Theme => Some(&THEME_CHOICES),
        Field::Motion => Some(&MOTION_CHOICES),
        _ => None,
    }
}

fn matching_choices(picker: &PickerState) -> Vec<Choice> {
    let query = picker.query.to_lowercase();
    choices(picker.field)
        .unwrap_or_default()
        .iter()
        .filter(|choice| query.is_empty() || choice.label.to_lowercase().contains(&query))
        .copied()
        .collect()
}

fn choice_value(field: Field, settings: &Settings) -> &str {
    match field {
        Field::WeekStart => match settings.week.starts_on {
            WeekStart::Monday => "monday",
            WeekStart::Sunday => "sunday",
        },
        Field::QuarterCycle => match settings.quarter.cycle {
            QuarterCycle::Calendar => "calendar",
            QuarterCycle::JapanFiscal => "japanFiscal",
        },
        Field::Country => &settings.life.country,
        Field::ShowRemaining => {
            if settings.mac_os.show_remaining {
                "remaining"
            } else {
                "elapsed"
            }
        }
        Field::Precision => match settings.mac_os.precision {
            0 => "0",
            1 => "1",
            2 => "2",
            3 => "3",
            _ => "",
        },
        Field::MacAccent => &settings.mac_os.accent,
        Field::Theme => match settings.tui.theme {
            TuiTheme::Auto => "auto",
            TuiTheme::Color => "color",
            TuiTheme::Catppuccin => "catppuccin",
            TuiTheme::TokyoNight => "tokyoNight",
            TuiTheme::Gruvbox => "gruvbox",
            TuiTheme::Monochrome => "monochrome",
        },
        Field::Motion => match settings.tui.motion {
            TuiMotion::Full => "full",
            TuiMotion::Reduced => "reduced",
            TuiMotion::Off => "off",
        },
        _ => "",
    }
}

fn apply_choice(field: Field, choice: Choice, settings: &mut Settings) -> Result<(), String> {
    match field {
        Field::WeekStart => {
            settings.week.starts_on = match choice.value {
                "monday" => WeekStart::Monday,
                "sunday" => WeekStart::Sunday,
                _ => return Err("Unsupported week start".into()),
            }
        }
        Field::QuarterCycle => {
            settings.quarter.cycle = match choice.value {
                "calendar" => QuarterCycle::Calendar,
                "japanFiscal" => QuarterCycle::JapanFiscal,
                _ => return Err("Unsupported quarter cycle".into()),
            }
        }
        Field::Country => {
            settings.life.country = choice.value.into();
            if let Some(expectancy) = choice.expectancy {
                settings.life.expectancy_years = expectancy;
            }
        }
        Field::ShowRemaining => {
            settings.mac_os.show_remaining = match choice.value {
                "elapsed" => false,
                "remaining" => true,
                _ => return Err("Unsupported display mode".into()),
            }
        }
        Field::Precision => {
            settings.mac_os.precision = choice
                .value
                .parse()
                .map_err(|_| "Unsupported precision".to_string())?
        }
        Field::MacAccent => settings.mac_os.accent = choice.value.into(),
        Field::Theme => {
            settings.tui.theme = match choice.value {
                "auto" => TuiTheme::Auto,
                "color" => TuiTheme::Color,
                "catppuccin" => TuiTheme::Catppuccin,
                "tokyoNight" => TuiTheme::TokyoNight,
                "gruvbox" => TuiTheme::Gruvbox,
                "monochrome" => TuiTheme::Monochrome,
                _ => return Err("Unsupported theme".into()),
            }
        }
        Field::Motion => {
            settings.tui.motion = match choice.value {
                "full" => TuiMotion::Full,
                "reduced" => TuiMotion::Reduced,
                "off" => TuiMotion::Off,
                _ => return Err("Unsupported motion setting".into()),
            }
        }
        _ => return Err("This setting does not use a picker".into()),
    }
    settings.validate()
}

fn field_label(field: Field) -> &'static str {
    FIELDS
        .iter()
        .find(|spec| spec.field == field)
        .map_or("option", |spec| spec.label)
}

#[cfg(target_os = "macos")]
fn request_current_location() -> Result<(), String> {
    let mut child = Command::new("/usr/bin/open")
        .arg("-g")
        .arg("timescale://locate")
        .spawn()
        .map_err(|error| format!("Could not open the Timescale Mac app: {error}"))?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn request_current_location() -> Result<(), String> {
    Err("Current location needs a platform location service; enter coordinates here".into())
}

fn menu_rows<'a>(
    settings: &Settings,
    menu: &SettingsMenu,
    palette: ThemePalette,
) -> Vec<MenuRow<'a>> {
    let mut rows = Vec::new();
    let mut section = "";
    for (index, spec) in FIELDS.iter().enumerate() {
        if spec.section != section {
            section = spec.section;
            rows.push(MenuRow {
                field_index: None,
                line: Line::from(Span::styled(
                    section,
                    Style::default()
                        .fg(palette.accent)
                        .add_modifier(Modifier::BOLD),
                )),
            });
            rows.push(MenuRow {
                field_index: None,
                line: Line::default(),
            });
        }
        let selected = index == menu.selected;
        let label_style = if selected {
            Style::default()
                .fg(palette.accent)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(palette.muted)
        };
        let value = if selected {
            menu.editing
                .as_ref()
                .filter(|edit| edit.field == spec.field)
                .map(editing_value)
                .unwrap_or_else(|| field_value(spec.field, settings))
        } else {
            field_value(spec.field, settings)
        };
        rows.push(MenuRow {
            field_index: Some(index),
            line: Line::from(vec![
                Span::styled(if selected { "› " } else { "  " }, label_style),
                Span::styled(format!("{:<20}", spec.label), label_style),
                Span::styled(
                    value,
                    if selected {
                        Style::default()
                            .fg(palette.primary)
                            .add_modifier(Modifier::BOLD)
                    } else {
                        Style::default().fg(palette.primary)
                    },
                ),
            ]),
        });
        rows.push(MenuRow {
            field_index: None,
            line: Line::default(),
        });
    }
    rows
}

fn editing_value(edit: &EditState) -> String {
    let byte = char_byte_index(&edit.value, edit.cursor);
    format!("{}▏{}", &edit.value[..byte], &edit.value[byte..])
}

fn is_text_field(field: Field) -> bool {
    matches!(
        field,
        Field::DayStart
            | Field::DayEnd
            | Field::RoutineName
            | Field::RoutineDuration
            | Field::SolarLocation
            | Field::BirthDate
            | Field::Expectancy
    )
}

fn edit_hint(field: Field) -> &'static str {
    match field {
        Field::DayStart | Field::DayEnd => "HH:MM",
        Field::RoutineName => "name",
        Field::RoutineDuration => "hours",
        Field::SolarLocation => "latitude, longitude · blank clears",
        Field::BirthDate => "YYYY-MM-DD · blank clears",
        Field::Expectancy => "years from 1 to 150",
        _ => "type a value",
    }
}

fn editable_value(field: Field, settings: &Settings) -> String {
    match field {
        Field::SolarLocation => match (settings.solar.latitude, settings.solar.longitude) {
            (Some(latitude), Some(longitude)) => format!("{latitude}, {longitude}"),
            _ => String::new(),
        },
        Field::BirthDate => settings.life.birth_date.clone().unwrap_or_default(),
        Field::RoutineDuration => {
            let hours = f64::from(settings.routine.duration_minutes) / 60.0;
            if hours.fract() == 0.0 {
                format!("{hours:.0}")
            } else {
                format!("{hours:.2}").trim_end_matches('0').to_string()
            }
        }
        Field::Expectancy if settings.life.expectancy_years.fract() == 0.0 => {
            format!("{:.0}", settings.life.expectancy_years)
        }
        Field::Expectancy => settings.life.expectancy_years.to_string(),
        _ => field_value(field, settings),
    }
}

fn field_value(field: Field, settings: &Settings) -> String {
    match field {
        Field::DayStart => settings.day.start.clone(),
        Field::DayEnd => settings.day.end.clone(),
        Field::RoutineName => settings.routine.name.clone(),
        Field::RoutineDuration => format_duration_minutes(settings.routine.duration_minutes),
        Field::WeekStart => match settings.week.starts_on {
            WeekStart::Monday => "Monday",
            WeekStart::Sunday => "Sunday",
        }
        .into(),
        Field::QuarterCycle => match settings.quarter.cycle {
            QuarterCycle::Calendar => "Calendar",
            QuarterCycle::JapanFiscal => "Japan fiscal",
        }
        .into(),
        Field::SolarEnabled => check(settings.solar.enabled),
        Field::SolarLocation => match (settings.solar.latitude, settings.solar.longitude) {
            (Some(latitude), Some(longitude)) => format!("{latitude:.4}, {longitude:.4}"),
            _ => "Not configured".into(),
        },
        Field::BirthDate => settings
            .life
            .birth_date
            .clone()
            .unwrap_or_else(|| "Not configured".into()),
        Field::Country => settings.life.country.clone(),
        Field::Expectancy => format!("{:.1} years", settings.life.expectancy_years),
        Field::Visible(period) => check(settings.visible.contains(&period)),
        Field::MacAccent => settings.mac_os.accent.clone(),
        Field::Precision => settings.mac_os.precision.to_string(),
        Field::ShowRemaining => if settings.mac_os.show_remaining {
            "Remaining"
        } else {
            "Elapsed"
        }
        .into(),
        Field::Theme => theme_name(&settings.tui.theme).into(),
        Field::Motion => motion_name(&settings.tui.motion).into(),
    }
}

fn check(enabled: bool) -> String {
    if enabled { "[x]" } else { "[ ]" }.into()
}

fn change_field(field: Field, settings: &mut Settings, direction: i8) -> Result<(), String> {
    match field {
        Field::DayStart => settings.day.start = adjust_time(&settings.day.start, direction)?,
        Field::DayEnd => settings.day.end = adjust_time(&settings.day.end, direction)?,
        Field::RoutineName => return Ok(()),
        Field::RoutineDuration => {
            let adjusted = i64::from(settings.routine.duration_minutes) + i64::from(direction) * 30;
            settings.routine.duration_minutes = adjusted.clamp(1, 10_080) as u32;
        }
        Field::WeekStart => {
            settings.week.starts_on = match settings.week.starts_on {
                WeekStart::Monday => WeekStart::Sunday,
                WeekStart::Sunday => WeekStart::Monday,
            }
        }
        Field::QuarterCycle => {
            settings.quarter.cycle = match settings.quarter.cycle {
                QuarterCycle::Calendar => QuarterCycle::JapanFiscal,
                QuarterCycle::JapanFiscal => QuarterCycle::Calendar,
            }
        }
        Field::SolarEnabled => settings.solar.enabled = !settings.solar.enabled,
        Field::Visible(period) => toggle_period(&mut settings.visible, period),
        Field::MacAccent => {
            settings.mac_os.accent = cycle(
                &["system", "orange", "blue", "green", "purple", "monochrome"],
                &settings.mac_os.accent,
                direction,
            )
            .into()
        }
        Field::Precision => {
            settings.mac_os.precision =
                cycle_index(settings.mac_os.precision as usize, 4, direction) as u8
        }
        Field::ShowRemaining => settings.mac_os.show_remaining = !settings.mac_os.show_remaining,
        Field::Theme => settings.tui.theme = cycle_theme(&settings.tui.theme, direction),
        Field::Motion => settings.tui.motion = cycle_motion(&settings.tui.motion, direction),
        Field::Country => {
            let index = COUNTRY_CHOICES
                .iter()
                .position(|choice| choice.value == settings.life.country)
                .unwrap_or(0);
            let choice = COUNTRY_CHOICES[cycle_index(index, COUNTRY_CHOICES.len(), direction)];
            settings.life.country = choice.value.into();
            settings.life.expectancy_years = choice.expectancy.unwrap_or(84.0);
        }
        Field::Expectancy => {
            settings.life.expectancy_years =
                (settings.life.expectancy_years + f64::from(direction)).clamp(1.0, 150.0)
        }
        Field::SolarLocation | Field::BirthDate => return Ok(()),
    }
    settings.validate()
}

fn save_text_value(
    field: Field,
    value: &str,
    settings: &mut Settings,
    store: &ConfigStore,
) -> Result<(), String> {
    let mut candidate = settings.clone();
    match field {
        Field::DayStart => candidate.day.start = value.trim().into(),
        Field::DayEnd => candidate.day.end = value.trim().into(),
        Field::RoutineName => candidate.routine.name = value.trim().into(),
        Field::RoutineDuration => {
            let hours: f64 = value
                .trim()
                .parse()
                .map_err(|_| "Invalid routine duration".to_string())?;
            candidate.routine.duration_minutes = (hours * 60.0).round() as u32;
        }
        Field::SolarLocation => {
            if value.trim().is_empty() || value.trim().eq_ignore_ascii_case("off") {
                candidate.solar.latitude = None;
                candidate.solar.longitude = None;
            } else {
                let (latitude, longitude) = value
                    .split_once(',')
                    .ok_or_else(|| "Use latitude, longitude".to_string())?;
                candidate.solar.latitude = Some(
                    latitude
                        .trim()
                        .parse()
                        .map_err(|_| "Invalid latitude".to_string())?,
                );
                candidate.solar.longitude = Some(
                    longitude
                        .trim()
                        .parse()
                        .map_err(|_| "Invalid longitude".to_string())?,
                );
            }
        }
        Field::BirthDate => {
            candidate.life.birth_date = (!value.trim().is_empty()).then(|| value.trim().into())
        }
        Field::Expectancy => {
            candidate.life.expectancy_years = value
                .trim()
                .trim_end_matches(" years")
                .parse()
                .map_err(|_| "Invalid life expectancy".to_string())?
        }
        _ => return Err("This setting is changed with arrows or Space".into()),
    }
    candidate.validate()?;
    store.save(&candidate)?;
    *settings = candidate;
    Ok(())
}

fn adjust_time(value: &str, direction: i8) -> Result<String, String> {
    let (hours, minutes) = value.split_once(':').ok_or("Invalid time")?;
    let total: i32 = hours.parse::<i32>().map_err(|_| "Invalid hour")? * 60
        + minutes.parse::<i32>().map_err(|_| "Invalid minute")?;
    let adjusted = (total + i32::from(direction) * 15).rem_euclid(24 * 60);
    Ok(format!("{:02}:{:02}", adjusted / 60, adjusted % 60))
}

fn format_duration_minutes(minutes: u32) -> String {
    let hours = minutes / 60;
    let remainder = minutes % 60;
    match (hours, remainder) {
        (0, minutes) => format!("{minutes} min"),
        (hours, 0) => format!("{hours} hr"),
        (hours, minutes) => format!("{hours} hr {minutes} min"),
    }
}

fn toggle_period(visible: &mut Vec<Period>, period: Period) {
    if visible.contains(&period) {
        visible.retain(|item| *item != period);
    } else {
        visible.push(period);
        visible.sort_by_key(|item| {
            Period::ALL
                .iter()
                .position(|period| period == item)
                .unwrap_or(0)
        });
    }
}

fn cycle<'a>(values: &'a [&str], current: &str, direction: i8) -> &'a str {
    let index = values
        .iter()
        .position(|value| *value == current)
        .unwrap_or(0);
    values[cycle_index(index, values.len(), direction)]
}

fn cycle_index(index: usize, length: usize, direction: i8) -> usize {
    (index as isize + direction as isize).rem_euclid(length as isize) as usize
}

fn cycle_theme(theme: &TuiTheme, direction: i8) -> TuiTheme {
    let values = [
        TuiTheme::Auto,
        TuiTheme::Color,
        TuiTheme::Catppuccin,
        TuiTheme::TokyoNight,
        TuiTheme::Gruvbox,
        TuiTheme::Monochrome,
    ];
    let index = values.iter().position(|value| value == theme).unwrap_or(0);
    values[cycle_index(index, values.len(), direction)].clone()
}

fn cycle_motion(motion: &TuiMotion, direction: i8) -> TuiMotion {
    let values = [TuiMotion::Full, TuiMotion::Reduced, TuiMotion::Off];
    let index = values.iter().position(|value| value == motion).unwrap_or(0);
    values[cycle_index(index, values.len(), direction)].clone()
}

fn theme_name(theme: &TuiTheme) -> &'static str {
    match theme {
        TuiTheme::Auto => "Auto",
        TuiTheme::Color => "Color",
        TuiTheme::Catppuccin => "Catppuccin",
        TuiTheme::TokyoNight => "Tokyo Night",
        TuiTheme::Gruvbox => "Gruvbox",
        TuiTheme::Monochrome => "Monochrome",
    }
}

fn motion_name(motion: &TuiMotion) -> &'static str {
    match motion {
        TuiMotion::Full => "Full",
        TuiMotion::Reduced => "Reduced",
        TuiMotion::Off => "Off",
    }
}

fn char_byte_index(value: &str, char_index: usize) -> usize {
    value
        .char_indices()
        .nth(char_index)
        .map_or(value.len(), |(index, _)| index)
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use ratatui::Terminal;
    use ratatui::backend::TestBackend;

    use super::*;

    #[test]
    fn time_arrows_wrap_in_fifteen_minute_steps() {
        assert_eq!(adjust_time("00:00", -1).unwrap(), "23:45");
        assert_eq!(adjust_time("23:50", 1).unwrap(), "00:05");
    }

    #[test]
    fn visible_periods_return_to_canonical_order() {
        let mut visible = vec![Period::Year, Period::Day];
        toggle_period(&mut visible, Period::Month);
        assert_eq!(visible, vec![Period::Day, Period::Month, Period::Year]);
    }

    #[test]
    fn country_picker_filters_and_applies_its_life_expectancy() {
        let picker = PickerState {
            field: Field::Country,
            query: "united".into(),
            selected: 0,
        };
        let matches = matching_choices(&picker);
        assert_eq!(
            matches
                .iter()
                .map(|choice| choice.label)
                .collect::<Vec<_>>(),
            vec!["United Kingdom", "United States"]
        );

        let mut settings = Settings::default();
        apply_choice(Field::Country, COUNTRY_CHOICES[6], &mut settings).unwrap();
        assert_eq!(settings.life.country, "Spain");
        assert_eq!(settings.life.expectancy_years, 84.0);
    }

    #[test]
    fn numeric_edit_values_do_not_include_display_units() {
        let settings = Settings::default();
        assert_eq!(editable_value(Field::Expectancy, &settings), "84");
        assert_eq!(editable_value(Field::RoutineDuration, &settings), "8");
    }

    #[test]
    fn unicode_cursor_uses_character_positions() {
        assert_eq!(char_byte_index("España", 5), 6);
    }

    #[test]
    fn scrolling_keeps_the_selection_centered_and_in_bounds() {
        assert_eq!(scroll_start(18, 10, 30), 14);
        assert_eq!(scroll_start(29, 10, 30), 20);
        assert_eq!(scroll_start(2, 10, 30), 0);
    }

    #[test]
    fn settings_follow_the_native_app_order() {
        assert_eq!(
            FIELDS.iter().map(|field| field.label).collect::<Vec<_>>(),
            vec![
                "Day",
                "Week",
                "Week starts on",
                "Month",
                "Quarter",
                "Quarter cycle",
                "Year",
                "Life estimate",
                "Starts",
                "Ends",
                "Name",
                "Duration",
                "Show sunrise and sunset",
                "Location",
                "Birth date",
                "Country",
                "Life expectancy",
                "Display",
                "Decimal places",
                "Accent",
                "Theme",
                "Motion",
            ]
        );
    }

    #[test]
    fn a_small_terminal_scrolls_to_the_selected_setting() {
        let mut menu = SettingsMenu::new();
        menu.selected = FIELDS.len() - 1;
        let settings = Settings::default();
        let backend = TestBackend::new(64, 16);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal
            .draw(|frame| menu.draw(frame, &settings, super::super::theme_palette(&settings)))
            .unwrap();

        let output = terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect::<String>();
        assert!(output.contains("Motion"));
        assert!(output.contains("Full"));
    }

    #[test]
    fn valid_edits_persist_and_invalid_edits_are_atomic() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "timescale-settings-{}-{unique}.json",
            std::process::id()
        ));
        let store = ConfigStore::new(path.clone());
        let mut settings = Settings::default();

        save_text_value(Field::DayStart, "07:30", &mut settings, &store).unwrap();
        assert_eq!(store.load().unwrap().day.start, "07:30");

        let saved = settings.clone();
        assert!(save_text_value(Field::BirthDate, "not-a-date", &mut settings, &store).is_err());
        assert_eq!(settings, saved);
        assert_eq!(store.load().unwrap(), saved);

        fs::remove_file(path).unwrap();
    }
}
