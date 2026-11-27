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

/// Build `(system_prompt, user_prompt)` for context-aware numbered subtitle batch translation.
///
/// Each cue is tagged with `[idx]` and multi-line cues are collapsed with ` / ` so the LLM
/// preserves 1:1 cue boundaries cleanly across both OpenAI-compatible models and Bilibili
/// Index-Translate.
pub fn build_subtitle_batch_prompt(
    lines: &[(usize, String)],
    context: &[String],
    target_lang: &str,
    media_title: Option<&str>,
    is_bilibili_index: bool,
) -> (Option<String>, String) {
    let mut numbered = String::new();
    for (idx, text) in lines {
        let one_line = text
            .replace("\r\n", "\n")
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .collect::<Vec<_>>()
            .join(" / ");
        numbered.push_str(&format!("[{idx}] {one_line}\n"));
    }

    let ctx_block = if context.is_empty() {
        String::new()
    } else {
        let joined = context
            .iter()
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join("\n");
        if joined.is_empty() {
            String::new()
        } else {
            format!("前文语境（仅作参考，不要输出）：\n{joined}\n\n")
        }
    };

    let title_hint = media_title
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|t| format!("影片：《{t}》\n"))
        .unwrap_or_default();

    if is_bilibili_index {
        let user = format!(
            "{title_hint}{ctx_block}请将以下每条带编号的字幕逐条自然地翻译为{target_lang}。\n严格保留每行开头的 `[编号]` 标记，一一对应输出，不要合并或拆分条目，也不要输出任何解释：\n\n{}",
            numbered.trim_end()
        );
        (None, user)
    } else {
        let system = format!(
            "You are a professional subtitle translator. Translate every numbered subtitle line naturally and idiomatically into {target_lang}. Preserve exact `[N]` prefixes, one line per input item, never merge or skip items, and output only the translated lines with no commentary or markdown fences."
        );
        let user = format!(
            "{title_hint}{ctx_block}Translate these subtitle lines into {target_lang}:\n{}",
            numbered.trim_end()
        );
        (Some(system), user)
    }
}

/// Parse an LLM numbered batch response back into `BTreeMap<cue_idx, translated_text>`.
///
/// Tolerates markdown code fences, `[12]`, `[12]:`, `12.`, `12)` prefixes, multi-line continuations,
/// and gracefully falls back to positional line matching when a model omits `[N]` markers.
pub fn parse_subtitle_batch_response(
    raw: &str,
    expected_indices: &[usize],
) -> std::collections::BTreeMap<usize, String> {
    use std::collections::{BTreeMap, HashSet};

    let expected_set: HashSet<usize> = expected_indices.iter().copied().collect();
    let cleaned = strip_code_fences(raw);
    let mut map: BTreeMap<usize, String> = BTreeMap::new();
    let mut last_idx: Option<usize> = None;

    for raw_line in cleaned.lines() {
        let trimmed = raw_line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some((idx, body)) = parse_numbered_prefix(trimmed) {
            if expected_set.contains(&idx) {
                let text = body.trim().replace(" / ", "\n");
                if !text.is_empty() {
                    map.insert(idx, text);
                }
                last_idx = Some(idx);
                continue;
            }
        }
        if let Some(prev) = last_idx {
            if let Some(entry) = map.get_mut(&prev) {
                entry.push('\n');
                entry.push_str(trimmed);
            }
        }
    }

    // Positional fallback if model stripped `[idx]` prefixes completely
    if map.is_empty() && !expected_indices.is_empty() {
        let non_empty: Vec<&str> = cleaned
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .collect();
        if non_empty.len() == expected_indices.len() {
            for (&idx, line) in expected_indices.iter().zip(non_empty.iter()) {
                map.insert(idx, line.replace(" / ", "\n"));
            }
        } else if expected_indices.len() == 1 && !non_empty.is_empty() {
            map.insert(expected_indices[0], non_empty.join("\n"));
        }
    }

    map
}

fn strip_code_fences(raw: &str) -> String {
    let trimmed = raw.trim();
    if let Some(rest) = trimmed.strip_prefix("```") {
        let body = rest
            .split_once('\n')
            .map(|(_, after)| after)
            .unwrap_or(rest);
        return body.trim_end().trim_end_matches("```").trim().to_string();
    }
    trimmed.to_string()
}

fn parse_numbered_prefix(line: &str) -> Option<(usize, &str)> {
    // Match `[12] text` or `[12]: text`
    if let Some(rest) = line.strip_prefix('[') {
        if let Some((num_str, after)) = rest.split_once(']') {
            if let Ok(idx) = num_str.trim().parse::<usize>() {
                let body = after
                    .trim_start()
                    .strip_prefix(':')
                    .or_else(|| after.trim_start().strip_prefix('：'))
                    .unwrap_or(after);
                return Some((idx, body.trim_start()));
            }
        }
    }
    // Match `12. text` or `12) text` or `12: text`
    let digits_len = line.bytes().take_while(|b| b.is_ascii_digit()).count();
    if digits_len > 0 && digits_len < line.len() {
        let rest = &line[digits_len..];
        let sep = rest.chars().next()?;
        if matches!(sep, '.' | ')' | ':' | '：' | '、') {
            let idx = line[..digits_len].parse::<usize>().ok()?;
            return Some((idx, rest[sep.len_utf8()..].trim_start()));
        }
    }
    None
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

    #[test]
    fn builds_and_parses_numbered_subtitle_batches() {
        let lines = vec![
            (10, "Good morning.".to_string()),
            (11, "First line\nSecond line".to_string()),
            (12, "Let's go!".to_string()),
        ];
        let (sys, user) = build_subtitle_batch_prompt(
            &lines,
            &["Earlier context.".to_string()],
            "简体中文",
            Some("Test Film"),
            false,
        );
        assert!(sys.is_some());
        assert!(user.contains("[10] Good morning."));
        assert!(user.contains("[11] First line / Second line"));

        let raw = "```text\n[10] 早上好。\n[11]: 第一行 / 第二行\n12. 我们走吧！\n```";
        let parsed = parse_subtitle_batch_response(raw, &[10, 11, 12]);
        assert_eq!(parsed.get(&10).map(String::as_str), Some("早上好。"));
        assert_eq!(parsed.get(&11).map(String::as_str), Some("第一行\n第二行"));
        assert_eq!(parsed.get(&12).map(String::as_str), Some("我们走吧！"));

        // Positional fallback when model strips `[idx]` markers (e.g. plain output)
        let plain = "早上好。\n第一行 / 第二行\n我们走吧！";
        let fallback = parse_subtitle_batch_response(plain, &[10, 11, 12]);
        assert_eq!(fallback.len(), 3);
        assert_eq!(fallback.get(&12).map(String::as_str), Some("我们走吧！"));
    }
}
