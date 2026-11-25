use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleCue {
    pub start_ms: i64,
    pub end_ms: i64,
    pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SubtitleFormat {
    Srt,
    Vtt,
    Ass,
}

/// Detect subtitle format from filename extension or file header.
pub fn detect_format(filename_or_ext: &str, content: &str) -> SubtitleFormat {
    let lower = filename_or_ext.to_lowercase();
    if lower.ends_with(".ass") || lower.ends_with(".ssa") || lower == "ass" || lower == "ssa" {
        return SubtitleFormat::Ass;
    }
    if lower.ends_with(".vtt") || lower == "vtt" || lower == "webvtt" {
        return SubtitleFormat::Vtt;
    }
    if content.trim_start().starts_with("WEBVTT") {
        return SubtitleFormat::Vtt;
    }
    if content.contains("[Script Info]") || content.contains("[Events]") {
        return SubtitleFormat::Ass;
    }
    SubtitleFormat::Srt
}

/// Parse SRT, WebVTT, or ASS/SSA subtitle text into normalized millisecond cues.
pub fn parse_subtitles(content: &str, format: SubtitleFormat) -> Vec<SubtitleCue> {
    let clean = content.trim_start_matches('\u{feff}').replace("\r\n", "\n");
    match format {
        SubtitleFormat::Srt | SubtitleFormat::Vtt => parse_srt_or_vtt(&clean),
        SubtitleFormat::Ass => parse_ass(&clean),
    }
}

/// Shift all cue timestamps by `offset_ms` (clamped at 0).
pub fn shift_cues(cues: &mut [SubtitleCue], offset_ms: i64) {
    for cue in cues.iter_mut() {
        cue.start_ms = (cue.start_ms + offset_ms).max(0);
        cue.end_ms = (cue.end_ms + offset_ms).max(cue.start_ms);
    }
}

/// Render normalized cues to standard WebVTT.
pub fn render_webvtt(cues: &[SubtitleCue]) -> String {
    let mut out = String::from("WEBVTT\n\n");
    for cue in cues {
        out.push_str(&format!(
            "{} --> {}\n{}\n\n",
            format_vtt_ts(cue.start_ms),
            format_vtt_ts(cue.end_ms),
            cue.text
        ));
    }
    out
}

fn parse_srt_or_vtt(content: &str) -> Vec<SubtitleCue> {
    let mut cues = Vec::new();
    for block in content.split("\n\n") {
        let lines: Vec<&str> = block
            .lines()
            .map(str::trim_end)
            .filter(|l| !l.trim().is_empty())
            .collect();
        if lines.is_empty() || lines[0].starts_with("WEBVTT") || lines[0].starts_with("NOTE") {
            continue;
        }
        let timing_idx = lines.iter().position(|l| l.contains("-->"));
        let Some(idx) = timing_idx else { continue };
        let Some((start_ms, end_ms)) = parse_arrow_timing(lines[idx]) else {
            continue;
        };
        let text = lines[idx + 1..].join("\n").trim().to_string();
        if !text.is_empty() {
            cues.push(SubtitleCue {
                start_ms,
                end_ms,
                text,
            });
        }
    }
    cues
}

fn parse_arrow_timing(line: &str) -> Option<(i64, i64)> {
    let (left, right_all) = line.split_once("-->")?;
    let right = right_all.split_whitespace().next()?;
    Some((parse_ts_ms(left.trim())?, parse_ts_ms(right.trim())?))
}

fn parse_ts_ms(ts: &str) -> Option<i64> {
    let norm = ts.replace(',', ".");
    let parts: Vec<&str> = norm.split(':').collect();
    let (h, m, s_ms) = match parts.len() {
        3 => (
            parts[0].parse::<i64>().ok()?,
            parts[1].parse::<i64>().ok()?,
            parts[2],
        ),
        2 => (0, parts[0].parse::<i64>().ok()?, parts[1]),
        _ => return None,
    };
    let (s, ms) = match s_ms.split_once('.') {
        Some((sec, frac)) => {
            let sec_v = sec.parse::<i64>().ok()?;
            let padded = format!("{frac:0<3}");
            let ms_v = padded[..3].parse::<i64>().ok()?;
            (sec_v, ms_v)
        }
        None => (s_ms.parse::<i64>().ok()?, 0),
    };
    Some(((h * 3600 + m * 60 + s) * 1000) + ms)
}

fn parse_ass(content: &str) -> Vec<SubtitleCue> {
    let mut cues = Vec::new();
    let mut in_events = false;
    let mut format_cols: Vec<String> = Vec::new();

    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.starts_with('[') && line.ends_with(']') {
            in_events = line.eq_ignore_ascii_case("[Events]");
            continue;
        }
        if !in_events {
            continue;
        }
        if let Some(rest) = line.strip_prefix("Format:") {
            format_cols = rest.split(',').map(|s| s.trim().to_lowercase()).collect();
            continue;
        }
        if let Some(rest) = line.strip_prefix("Dialogue:") {
            let start_col = format_cols.iter().position(|c| c == "start").unwrap_or(1);
            let end_col = format_cols.iter().position(|c| c == "end").unwrap_or(2);
            let text_col = format_cols.iter().position(|c| c == "text").unwrap_or(9);

            let parts: Vec<&str> = rest.splitn(text_col + 1, ',').collect();
            if parts.len() <= text_col {
                continue;
            }
            let Some(start_ms) = parse_ass_ts(parts[start_col].trim()) else {
                continue;
            };
            let Some(end_ms) = parse_ass_ts(parts[end_col].trim()) else {
                continue;
            };
            let text = clean_ass_text(parts[text_col]);
            if !text.is_empty() {
                cues.push(SubtitleCue {
                    start_ms,
                    end_ms,
                    text,
                });
            }
        }
    }
    cues
}

fn parse_ass_ts(ts: &str) -> Option<i64> {
    // H:MM:SS.cc (centiseconds)
    let parts: Vec<&str> = ts.split(':').collect();
    if parts.len() != 3 {
        return None;
    }
    let h = parts[0].parse::<i64>().ok()?;
    let m = parts[1].parse::<i64>().ok()?;
    let (s, cs) = parts[2].split_once('.')?;
    let sec = s.parse::<i64>().ok()?;
    let centis = cs.parse::<i64>().ok()?;
    Some((h * 3600 + m * 60 + sec) * 1000 + centis * 10)
}

fn clean_ass_text(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut in_brace = false;
    let chars: Vec<char> = raw.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '{' {
            in_brace = true;
            i += 1;
            continue;
        }
        if c == '}' {
            in_brace = false;
            i += 1;
            continue;
        }
        if !in_brace {
            if c == '\\' && i + 1 < chars.len() && matches!(chars[i + 1], 'N' | 'n') {
                out.push('\n');
                i += 2;
                continue;
            }
            out.push(c);
        }
        i += 1;
    }
    out.trim().to_string()
}

fn format_vtt_ts(ms: i64) -> String {
    let total_s = ms / 1000;
    let rem_ms = ms % 1000;
    let h = total_s / 3600;
    let m = (total_s % 3600) / 60;
    let s = total_s % 60;
    format!("{h:02}:{m:02}:{s:02}.{rem_ms:03}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_shifts_srt_and_ass() {
        let srt = "1\n00:00:01,500 --> 00:00:03,000\nHello World\n\n2\n00:00:04,000 --> 00:00:06,250\nSecond Line\n";
        let mut cues = parse_subtitles(srt, SubtitleFormat::Srt);
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0].start_ms, 1500);
        shift_cues(&mut cues, 500);
        assert_eq!(cues[0].start_ms, 2000);
        let vtt = render_webvtt(&cues);
        assert!(vtt.contains("00:00:02.000 --> 00:00:03.500"));

        let ass = "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:10.50,0:00:12.00,Default,,0,0,0,,{\\i1}Line 1\\NLine 2\n";
        let ass_cues = parse_subtitles(ass, SubtitleFormat::Ass);
        assert_eq!(ass_cues.len(), 1);
        assert_eq!(ass_cues[0].start_ms, 10_500);
        assert_eq!(ass_cues[0].text, "Line 1\nLine 2");
    }
}
