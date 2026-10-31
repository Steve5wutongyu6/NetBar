//! Hand-rolled JSON: a small total parser (no panics, depth/byte/length
//! guarded) and a serializer whose only fallible step is UTF-8 validation.
//!
//! The parser is deliberately strict RFC 8259: no trailing commas, no
//! comments, no unquoted keys, exactly one top-level value, and only
//! whitespace may trail it. Every failure is an [`Error`], never a panic, and
//! the recursion budget is checked *before* descending, so hostile nesting
//! cannot smash the stack.

/// Hard ceiling on parser nesting. Stack frames are tiny in release, but the
/// bound is applied to debug builds and tests too.
pub const MAX_DEPTH: usize = 128;

/// Inputs longer than this are rejected before any work happens.
pub const MAX_BYTES: usize = 16 * 1024 * 1024;

/// Objects/arrays/elements nested inside a single document...
pub const MAX_ARRAY_ITEMS: usize = 100_000;

/// Where a document failed to parse: an absolute byte offset into the input.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Error {
    /// Byte offset in the input at which parsing gave up.
    pub offset: usize,
}

impl Error {
    const fn at(offset: usize) -> Self {
        Self { offset }
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "invalid JSON at byte {}", self.offset)
    }
}

/// A parsed JSON value. Object keys keep insertion order and may repeat (the
/// model layer decides which duplicate wins); numbers keep their raw literal
/// so integers below 2^53 stay exact.
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Number(String),
    String(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    /// Literal reading of the value; only valid JSON literals decode.
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(value) => Some(*value),
            _ => None,
        }
    }

    /// Integer reading: integral literals and integral floats only. Out-of-range
    /// or fractional numbers yield `None`.
    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Value::Number(raw) => integral_text(raw).and_then(|text| text.parse().ok()),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::String(text) => Some(text),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(items) => Some(items),
            _ => None,
        }
    }

    /// Last-wins lookup, matching Foundation's JSON semantics closely enough.
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(entries) => entries
                .iter()
                .rev()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value),
            _ => None,
        }
    }

    pub fn is_object(&self) -> bool {
        matches!(self, Value::Object(_))
    }
}

/// Reduces a JSON number literal to its exact integer form, or `None` when the
/// value is fractional or does not fit in `i64`. `5`, `5.0`, `50e-1` and
/// `0.5e1` all reduce to `5`; `1.5` and `1e400` do not. The literal is kept as
/// text until here so large integers never round-trip through a float.
fn integral_text(raw: &str) -> Option<String> {
    let (negative, unsigned) = match raw.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, raw),
    };
    let (mantissa, exponent) = match unsigned.find(['e', 'E']) {
        Some(index) => (
            &unsigned[..index],
            unsigned[index + 1..].parse::<i64>().ok()?,
        ),
        None => (unsigned, 0),
    };
    let (whole, fraction) = match mantissa.find('.') {
        Some(index) => (&mantissa[..index], &mantissa[index + 1..]),
        None => (mantissa, ""),
    };
    if whole.is_empty() && fraction.is_empty() {
        return None;
    }
    let mut digits = String::with_capacity(whole.len() + fraction.len());
    digits.push_str(whole);
    digits.push_str(fraction);

    // The decimal point sits after `whole.len()` digits; the exponent moves it.
    let shift = exponent.checked_sub(fraction.len() as i64)?;
    if shift < 0 {
        let keep = digits.len() as i64 + shift;
        if keep < 0 {
            return None;
        }
        let keep = keep as usize;
        if digits[keep..].chars().any(|digit| digit != '0') {
            return None;
        }
        digits.truncate(keep);
    } else {
        // Beyond i64's own digit count nothing can be representable.
        if shift > 20 {
            return None;
        }
        digits.push_str(&"0".repeat(shift as usize));
    }
    if digits.is_empty() {
        return None;
    }
    let value: i64 = digits.parse().ok()?;
    Some(if negative { -value } else { value }.to_string())
}

/// Parses one UTF-8 JSON document. See the module docs for the guarantees.
pub fn parse(input: &str) -> Result<Value, Error> {
    if input.len() > MAX_BYTES {
        return Err(Error::at(MAX_BYTES));
    }
    let mut parser = Parser {
        bytes: input.as_bytes(),
        offset: 0,
        depth: 0,
    };
    parser.skip_whitespace();
    let value = parser.parse_value()?;
    parser.skip_whitespace();
    if parser.offset != parser.bytes.len() {
        return Err(Error::at(parser.offset));
    }
    Ok(value)
}

struct Parser<'a> {
    bytes: &'a [u8],
    offset: usize,
    depth: usize,
}

impl Parser<'_> {
    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.offset).copied()
    }

    fn bump(&mut self) -> Option<u8> {
        let byte = self.peek()?;
        self.offset += 1;
        Some(byte)
    }

    fn skip_whitespace(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.offset += 1;
        }
    }

    fn expect(&mut self, wanted: u8) -> Result<(), Error> {
        match self.bump() {
            Some(byte) if byte == wanted => Ok(()),
            _ => Err(Error::at(self.offset.saturating_sub(1))),
        }
    }

    fn enter(&mut self) -> Result<(), Error> {
        if self.depth >= MAX_DEPTH {
            return Err(Error::at(self.offset));
        }
        self.depth += 1;
        Ok(())
    }

    fn leave(&mut self) {
        self.depth = self.depth.saturating_sub(1);
    }

    fn parse_value(&mut self) -> Result<Value, Error> {
        match self.peek() {
            Some(b'{') => self.parse_object(),
            Some(b'[') => self.parse_array(),
            Some(b'"') => self.parse_string().map(Value::String),
            Some(b't') => self.parse_literal("true", Value::Bool(true)),
            Some(b'f') => self.parse_literal("false", Value::Bool(false)),
            Some(b'n') => self.parse_literal("null", Value::Null),
            Some(b'-' | b'0'..=b'9') => self.parse_number().map(Value::Number),
            _ => Err(Error::at(self.offset)),
        }
    }

    fn parse_literal(&mut self, word: &str, value: Value) -> Result<Value, Error> {
        let end = self.offset.saturating_add(word.len());
        if self.bytes.get(self.offset..end) == Some(word.as_bytes()) {
            self.offset = end;
            Ok(value)
        } else {
            Err(Error::at(self.offset))
        }
    }

    fn parse_object(&mut self) -> Result<Value, Error> {
        self.enter()?;
        self.expect(b'{')?;
        let mut entries = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b'}') {
            self.offset += 1;
            self.leave();
            return Ok(Value::Object(entries));
        }
        loop {
            self.skip_whitespace();
            if entries.len() >= MAX_ARRAY_ITEMS {
                return Err(Error::at(self.offset));
            }
            let key = self.parse_string()?;
            self.skip_whitespace();
            self.expect(b':')?;
            self.skip_whitespace();
            let value = self.parse_value()?;
            entries.push((key, value));
            self.skip_whitespace();
            match self.bump() {
                Some(b',') => continue,
                Some(b'}') => break,
                _ => return Err(Error::at(self.offset.saturating_sub(1))),
            }
        }
        self.leave();
        Ok(Value::Object(entries))
    }

    fn parse_array(&mut self) -> Result<Value, Error> {
        self.enter()?;
        self.expect(b'[')?;
        let mut items = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b']') {
            self.offset += 1;
            self.leave();
            return Ok(Value::Array(items));
        }
        loop {
            if items.len() >= MAX_ARRAY_ITEMS {
                return Err(Error::at(self.offset));
            }
            self.skip_whitespace();
            items.push(self.parse_value()?);
            self.skip_whitespace();
            match self.bump() {
                Some(b',') => continue,
                Some(b']') => break,
                _ => return Err(Error::at(self.offset.saturating_sub(1))),
            }
        }
        self.leave();
        Ok(Value::Array(items))
    }

    fn parse_string(&mut self) -> Result<String, Error> {
        self.expect(b'"')?;
        let mut out = String::new();
        // Deliberately re-scanning from the start of each plain run keeps this
        // simple; runs are copied wholesale and escapes handled one at a time.
        loop {
            let start = self.offset;
            while let Some(byte) = self.peek() {
                if byte == b'"' || byte == b'\\' || byte < 0x20 {
                    break;
                }
                self.offset += 1;
            }
            // SAFETY-free: `parse` is only handed valid UTF-8 and every stop
            // byte above is ASCII, so both endpoints are char boundaries.
            let run = &self.bytes[start..self.offset];
            match std::str::from_utf8(run) {
                Ok(text) => out.push_str(text),
                Err(_) => return Err(Error::at(start)),
            }
            match self.peek() {
                Some(b'"') => {
                    self.offset += 1;
                    return Ok(out);
                }
                Some(b'\\') => {
                    self.offset += 1;
                    out.push(self.parse_escape()?);
                }
                Some(_) => return Err(Error::at(self.offset)),
                None => return Err(Error::at(self.offset)),
            }
        }
    }

    fn parse_escape(&mut self) -> Result<char, Error> {
        match self.bump() {
            Some(b'"') => Ok('"'),
            Some(b'\\') => Ok('\\'),
            Some(b'/') => Ok('/'),
            Some(b'b') => Ok('\u{0008}'),
            Some(b'f') => Ok('\u{000C}'),
            Some(b'n') => Ok('\n'),
            Some(b'r') => Ok('\r'),
            Some(b't') => Ok('\t'),
            Some(b'u') => {
                let first = self.parse_hex4()?;
                let code = match first {
                    // Lone low surrogates are unrepresentable and rejected.
                    0xDC00..=0xDFFF => return Err(Error::at(self.offset)),
                    0xD800..=0xDBFF => {
                        if self.bytes.get(self.offset..self.offset + 2) != Some(b"\\u") {
                            return Err(Error::at(self.offset));
                        }
                        self.offset += 2;
                        let second = self.parse_hex4()?;
                        if !(0xDC00..=0xDFFF).contains(&second) {
                            return Err(Error::at(self.offset));
                        }
                        0x1_0000 + (u32::from(first - 0xD800) << 10) + u32::from(second - 0xDC00)
                    }
                    other => u32::from(other),
                };
                char::from_u32(code).ok_or(Error::at(self.offset))
            }
            _ => Err(Error::at(self.offset.saturating_sub(1))),
        }
    }

    fn parse_hex4(&mut self) -> Result<u16, Error> {
        let mut value = 0u16;
        for _ in 0..4 {
            let nibble = match self.bump() {
                Some(byte @ b'0'..=b'9') => u16::from(byte - b'0'),
                Some(byte @ b'a'..=b'f') => u16::from(byte - b'a') + 10,
                Some(byte @ b'A'..=b'F') => u16::from(byte - b'A') + 10,
                _ => return Err(Error::at(self.offset)),
            };
            value = value.wrapping_mul(16).wrapping_add(nibble);
        }
        Ok(value)
    }

    /// Strict RFC 8259 number grammar. Literals longer than 512 bytes are
    /// rejected so absurd exponents cannot be built up at all.
    fn parse_number(&mut self) -> Result<String, Error> {
        let start = self.offset;
        if self.peek() == Some(b'-') {
            self.offset += 1;
        }
        match self.peek() {
            Some(b'0') => self.offset += 1,
            Some(b'1'..=b'9') => {
                while matches!(self.peek(), Some(b'0'..=b'9')) {
                    self.offset += 1;
                }
            }
            _ => return Err(Error::at(self.offset)),
        }
        if self.peek() == Some(b'.') {
            self.offset += 1;
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(Error::at(self.offset));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.offset += 1;
            }
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.offset += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.offset += 1;
            }
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(Error::at(self.offset));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.offset += 1;
            }
        }
        if self.offset - start > 512 {
            return Err(Error::at(start));
        }
        // The grammar is pure ASCII; infallible by construction.
        Ok(String::from_utf8_lossy(&self.bytes[start..self.offset]).into_owned())
    }
}

/// Appends `value` as a quoted JSON string literal. Quotes, backslashes and
/// every C0 control character are escaped; printable UTF-8 (including
/// CJK) is emitted untouched.
pub fn write_string(out: &mut String, value: &str) {
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{0008}' => out.push_str("\\b"),
            '\u{000C}' => out.push_str("\\f"),
            '\u{0000}'..='\u{001F}' => {
                let digits = u32::from(ch);
                out.push_str("\\u");
                for shift in [12, 8, 4, 0] {
                    out.push(
                        char::from_digit((digits >> shift) & 0xF, 16)
                            .map_or('0', |hex| hex.to_ascii_uppercase()),
                    );
                }
            }
            other => out.push(other),
        }
    }
    out.push('"');
}

/// Appends `value` as a JSON string literal, or `null` when absent.
pub fn write_opt_string(out: &mut String, value: Option<&str>) {
    match value {
        Some(text) => write_string(out, text),
        None => out.push_str("null"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_err(input: &str) -> Error {
        parse(input).expect_err("should reject")
    }

    #[test]
    fn parses_scalars_and_containers() {
        assert_eq!(parse("null"), Ok(Value::Null));
        assert_eq!(parse("true"), Ok(Value::Bool(true)));
        assert_eq!(parse(" false "), Ok(Value::Bool(false)));
        assert_eq!(parse("0"), Ok(Value::Number("0".into())));
        assert_eq!(parse("-12.5e3"), Ok(Value::Number("-12.5e3".into())));
        assert_eq!(
            parse(r#"{"a":1,"b":[true,null]}"#),
            Ok(Value::Object(vec![
                ("a".into(), Value::Number("1".into())),
                (
                    "b".into(),
                    Value::Array(vec![Value::Bool(true), Value::Null])
                ),
            ]))
        );
    }

    #[test]
    fn rejects_malformed_documents() {
        for bad in [
            "",
            " ",
            "{",
            "}",
            "{\"a\"}",
            "{\"a\":}",
            "[1,]",
            "{\"a\":1,}",
            "{'a':1}",
            "01",
            "-",
            "1.",
            "1e",
            "+1",
            "tru",
            "truthy",
            "nul",
            "[1] 2",
            "{\"a\":1} x",
            "// comment\n1",
            "[1 2]",
            "\"unterminated",
            "\"bad \\x escape\"",
            "\"bad \\u12 escape\"",
            "\"lone \\ud800\"",
            "\"lone \\udc00\"",
            "\"raw control \u{1}\"",
            "\u{feff}1",
            "NaN",
            "Infinity",
        ] {
            assert!(parse(bad).is_err(), "should reject {bad:?}");
        }
    }

    #[test]
    fn error_offsets_point_into_input() {
        for bad in [
            "{\"a\":1",
            "  {\"a\":1,}",
            "[1,",
            "\"unterminated",
            "tru",
            "01",
        ] {
            let error = parse_err(bad);
            assert!(
                error.offset <= bad.len(),
                "offset {} is outside {bad:?}",
                error.offset
            );
        }
    }

    #[test]
    fn depth_is_bounded_before_descending() {
        let deep = "[".repeat(MAX_DEPTH + 1);
        assert!(parse(&deep).is_err());
        // One level shallower than the cap, with matching closers, parses.
        let ok = format!("{}{}", "[".repeat(MAX_DEPTH), "]".repeat(MAX_DEPTH));
        assert!(parse(&ok).is_ok());
    }

    #[test]
    fn oversized_documents_are_rejected_before_parsing() {
        let huge = format!("\"{}\"", "a".repeat(MAX_BYTES));
        let error = parse_err(&huge);
        assert_eq!(error.offset, MAX_BYTES);
    }

    #[test]
    fn handles_escapes_and_surrogate_pairs() {
        let value = parse(r#""a\"b\\c\/d\b\f\n\r\t\u00e9\u2026\ud83d\ude00""#).expect("valid");
        assert_eq!(
            value.as_str(),
            Some("a\"b\\c/d\u{8}\u{c}\n\r\t\u{e9}\u{2026}\u{1F600}")
        );
        let value = parse("\"\\u4E2D\\u6587\"").expect("valid");
        assert_eq!(value.as_str(), Some("中文"));
    }

    #[test]
    fn preserves_non_ascii_text_byte_exact() {
        let value = parse(r#""吴同宇的iPhone""#).expect("valid");
        assert_eq!(value.as_str(), Some("吴同宇的iPhone"));
    }

    #[test]
    fn integers_above_the_float_mantissa_stay_exact() {
        let value = parse("9007199254740993").expect("valid");
        assert_eq!(value.as_i64(), Some(9007199254740993));
        assert_eq!(parse("1.5").expect("valid").as_i64(), None);
        assert_eq!(parse("9223372036854775808").expect("valid").as_i64(), None);
        assert_eq!(Value::Bool(true).as_i64(), None);
    }

    #[test]
    fn duplicate_keys_resolve_to_the_last_value() {
        let value = parse(r#"{"a":1,"a":2}"#).expect("valid");
        assert_eq!(value.get("a").and_then(Value::as_i64), Some(2));
        assert_eq!(value.get("missing"), None);
        assert_eq!(Value::Null.get("a"), None);
    }

    #[test]
    fn serializer_escapes_and_round_trips() {
        let mut out = String::new();
        write_string(&mut out, "q\"b\\s\n\tt\u{1}\u{1f}中文\u{2026}");
        assert_eq!(out, "\"q\\\"b\\\\s\\n\\tt\\u0001\\u001F中文\u{2026}\"");
        let round_tripped = parse(&out).expect("valid").as_str().map(str::to_owned);
        let original = "q\"b\\s\n\tt\u{1}\u{1f}中文\u{2026}".to_owned();
        assert_eq!(round_tripped, Some(original));
        let mut out = String::new();
        write_opt_string(&mut out, None);
        assert_eq!(out, "null");
    }
}
