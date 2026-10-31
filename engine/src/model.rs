//! Wire models: `NBEngineInput` / `NBEngineOutput` as plain Rust types, plus
//! decode (defaults for every missing field, no panics) and encode.

use crate::json::{self, Value};

/// `schemaVersion` of the wire format we speak.
pub const SCHEMA_VERSION: i64 = 1;

/// One scanned BSS after wire decoding. `ssid == None` marks an entry the OS
/// did not expose (anonymous network).
#[derive(Clone, Debug, PartialEq)]
pub struct Network {
    pub ssid: Option<String>,
    /// Hardware address, used as the fallback identity for an entry whose name
    /// macOS withheld.
    pub bssid: Option<String>,
    /// Saved-profile name this ESSID belongs to. CoreWLAN keeps profile names
    /// when macOS redacts SSIDs, so this survives without Location Services.
    pub service_name: Option<String>,
    pub rssi: i64,
    pub known: bool,
    pub personal_hotspot: bool,
    pub hotspot_network: i64,
    pub hotspot_battery: i64,
    /// 0 Open, 1 WEP, 2 WPA, 3 WPA2, 4 WPA3, 5 Enterprise.
    pub security: i64,
}

/// The whole request.
#[derive(Clone, Debug, PartialEq)]
pub struct Input {
    pub power_on: bool,
    pub current_ssid: Option<String>,
    pub connected_name_redacted: bool,
    pub interface_name: Option<String>,
    pub current_rssi: i64,
    /// Relayed for diagnostics only; the engine does not render it.
    #[allow(dead_code)]
    pub scanning: bool,
    /// Saved-network names from the interface configuration.
    pub preferred_networks: Vec<String>,
    /// Show every remaining network instead of the folded default.
    pub reveal_other: bool,
    /// What the radio reports about the joined network, independent of the scan.
    pub current_is_personal_hotspot: bool,
    pub current_hotspot_network: i64,
    pub current_hotspot_battery: i64,
    pub networks: Vec<Network>,
}

impl Default for Input {
    /// Every field's wire default. `power_on: false` is rule B's "all off".
    fn default() -> Self {
        Self {
            power_on: false,
            current_ssid: None,
            connected_name_redacted: false,
            interface_name: None,
            current_rssi: 0,
            scanning: false,
            preferred_networks: Vec::new(),
            reveal_other: false,
            current_is_personal_hotspot: false,
            current_hotspot_network: 0,
            current_hotspot_battery: 0,
            networks: Vec::new(),
        }
    }
}

impl Input {
    /// Decodes any parsed JSON value; non-objects yield the power-off default.
    pub fn decode(value: &Value) -> Self {
        let Value::Object(_) = value else {
            return Self::default();
        };
        Self {
            power_on: bool_field(value, "powerOn"),
            current_ssid: string_field(value, "currentSSID"),
            connected_name_redacted: bool_field(value, "connectedNameRedacted"),
            interface_name: string_field(value, "interfaceName"),
            current_rssi: int_field(value, "currentRSSI"),
            scanning: bool_field(value, "scanning"),
            preferred_networks: match value.get("preferredNetworks").and_then(Value::as_array) {
                Some(entries) => entries
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect(),
                None => Vec::new(),
            },
            reveal_other: bool_field(value, "revealOther"),
            current_is_personal_hotspot: bool_field(value, "currentIsPersonalHotspot"),
            current_hotspot_network: int_field(value, "currentHotspotNetwork"),
            current_hotspot_battery: int_field(value, "currentHotspotBattery"),
            networks: match value.get("networks").and_then(Value::as_array) {
                Some(entries) => entries.iter().map(Network::decode).collect(),
                None => Vec::new(),
            },
        }
    }
}

impl Network {
    fn decode(value: &Value) -> Self {
        Self {
            ssid: string_field(value, "ssid"),
            bssid: string_field(value, "bssid"),
            service_name: string_field(value, "serviceName"),
            rssi: int_field(value, "rssi"),
            known: bool_field(value, "known"),
            personal_hotspot: bool_field(value, "personalHotspot"),
            hotspot_network: int_field(value, "hotspotNetwork"),
            hotspot_battery: int_field(value, "hotspotBattery"),
            security: int_field(value, "security"),
        }
    }
}

fn bool_field(object: &Value, key: &str) -> bool {
    object.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn int_field(object: &Value, key: &str) -> i64 {
    object.get(key).and_then(Value::as_i64).unwrap_or(0)
}

/// `None` for absent fields, JSON null, or non-strings — all of which the
/// contract treats as "not exposed".
fn string_field(object: &Value, key: &str) -> Option<String> {
    object.get(key).and_then(Value::as_str).map(str::to_owned)
}

/// `NBItemRole` in `NBNodeJSON.h`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i64)]
pub enum Role {
    Header = 0,
    Network = 1,
    OtherNetworks = 2,
    Settings = 3,
}

/// `NBItemSection` in `NBNodeJSON.h`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i64)]
pub enum Section {
    Hotspot = 0,
    Known = 1,
    Other = 2,
    Footer = 3,
}

/// `NBDetailKind` in `NBNodeJSON.h`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i64)]
pub enum DetailKind {
    None = 0,
    Lock = 1,
    AppleHotspot = 2,
}

/// `NBCellIndicator` in `NBNodeJSON.h`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[repr(i64)]
pub enum Cell {
    #[default]
    None = 0,
    FourG = 1,
    FiveG = 2,
}

impl Cell {
    /// Coerces an untrusted wire value: only 1 and 2 are meaningful.
    pub const fn from_i64(raw: i64) -> Self {
        match raw {
            1 => Cell::FourG,
            2 => Cell::FiveG,
            _ => Cell::None,
        }
    }
}

/// One rendered menu row.
#[derive(Clone, Debug, PartialEq)]
pub struct Item {
    pub role: Role,
    pub section: Section,
    pub id: String,
    pub title: Option<String>,
    pub ssid: Option<String>,
    pub security: i64,
    pub rssi: i64,
    pub is_joined: bool,
    pub detail_kind: DetailKind,
    pub cell: Cell,
    pub battery: u8,
    pub strength: u8,
    pub redacted: bool,
}

impl Item {
    /// A section header row; only title, role and section carry meaning.
    pub fn header(section: Section, id: &str, title: &str) -> Self {
        Self {
            role: Role::Header,
            section,
            id: id.to_owned(),
            title: Some(title.to_owned()),
            ssid: None,
            security: 0,
            rssi: 0,
            is_joined: false,
            detail_kind: DetailKind::None,
            cell: Cell::None,
            battery: 0,
            strength: 0,
            redacted: false,
        }
    }

    /// A network row. `strength` is filled in by the caller (rule A) so the
    /// ranking layer owns the bars arithmetic.
    pub fn network(section: Section, id: String, ssid: &str) -> Self {
        Self {
            role: Role::Network,
            section,
            id,
            title: Some(ssid.to_owned()),
            ssid: Some(ssid.to_owned()),
            security: 0,
            rssi: 0,
            is_joined: false,
            detail_kind: DetailKind::None,
            cell: Cell::None,
            battery: 0,
            strength: 0,
            redacted: false,
        }
    }

    /// The single "Other Networks" aggregator row (rule E.4).
    pub fn other_aggregator() -> Self {
        Self {
            role: Role::OtherNetworks,
            section: Section::Other,
            id: "other.row".to_owned(),
            title: Some("Other Networks".to_owned()),
            ..Self::header(Section::Other, "other.row", "Other Networks")
        }
    }

    /// The settings footer row (rule E.5; U+2026 horizontal ellipsis).
    pub fn settings_footer() -> Self {
        Self {
            role: Role::Settings,
            section: Section::Footer,
            ..Self::header(Section::Footer, "footer.settings", "Wi-Fi Settings\u{2026}")
        }
    }
}

/// The rendered menu plus status-line data.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Output {
    pub status_title: Option<String>,
    pub status_needs_setup: bool,
    pub items: Vec<Item>,
    pub hidden_other_count: i64,
    pub connected_name: Option<String>,
    pub connected_is_hotspot: bool,
    pub connected_cell: Cell,
    pub connected_battery: i64,
    pub connected_strength: u8,
}

impl Output {
    /// Serializes to the exact `NBEngineOutput` wire format.
    pub fn encode(&self) -> String {
        let mut out = String::with_capacity(256);
        out.push_str("{\"schemaVersion\":");
        out.push_str(&SCHEMA_VERSION.to_string());
        out.push_str(",\"statusTitle\":");
        json::write_opt_string(&mut out, self.status_title.as_deref());
        out.push_str(",\"statusNeedsSetup\":");
        out.push_str(bool_text(self.status_needs_setup));
        out.push_str(",\"items\":[");
        for (index, item) in self.items.iter().enumerate() {
            if index > 0 {
                out.push(',');
            }
            item.encode(&mut out);
        }
        out.push_str("],\"hiddenOtherCount\":");
        out.push_str(&self.hidden_other_count.to_string());
        out.push_str(",\"connectedName\":");
        json::write_opt_string(&mut out, self.connected_name.as_deref());
        out.push_str(",\"connectedIsHotspot\":");
        out.push_str(bool_text(self.connected_is_hotspot));
        out.push_str(",\"connectedCell\":");
        out.push_str(&(self.connected_cell as i64).to_string());
        out.push_str(",\"connectedBattery\":");
        out.push_str(&self.connected_battery.to_string());
        out.push_str(",\"connectedStrength\":");
        out.push_str(&self.connected_strength.to_string());
        out.push('}');
        out
    }
}

impl Item {
    fn encode(&self, out: &mut String) {
        out.push_str("{\"role\":");
        out.push_str(&(self.role as i64).to_string());
        out.push_str(",\"section\":");
        out.push_str(&(self.section as i64).to_string());
        out.push_str(",\"id\":");
        json::write_string(out, &self.id);
        out.push_str(",\"title\":");
        json::write_opt_string(out, self.title.as_deref());
        out.push_str(",\"ssid\":");
        json::write_opt_string(out, self.ssid.as_deref());
        out.push_str(",\"security\":");
        out.push_str(&self.security.to_string());
        out.push_str(",\"rssi\":");
        out.push_str(&self.rssi.to_string());
        out.push_str(",\"isJoined\":");
        out.push_str(bool_text(self.is_joined));
        out.push_str(",\"detailKind\":");
        out.push_str(&(self.detail_kind as i64).to_string());
        out.push_str(",\"cell\":");
        out.push_str(&(self.cell as i64).to_string());
        out.push_str(",\"battery\":");
        out.push_str(&self.battery.to_string());
        out.push_str(",\"strength\":");
        out.push_str(&self.strength.to_string());
        out.push_str(",\"redacted\":");
        out.push_str(bool_text(self.redacted));
        out.push('}');
    }
}

const fn bool_text(value: bool) -> &'static str {
    if value {
        "true"
    } else {
        "false"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_applies_defaults_for_missing_and_odd_fields() {
        let value = json::parse(
            r#"{"powerOn":true,"currentRSSI":"oops","networks":[{"ssid":7,"rssi":-50}]}"#,
        )
        .expect("valid");
        let input = Input::decode(&value);
        assert!(input.power_on);
        assert_eq!(input.current_rssi, 0);
        assert_eq!(input.current_ssid, None);
        assert_eq!(input.networks.len(), 1);
        assert_eq!(input.networks[0].ssid, None);
        assert_eq!(input.networks[0].rssi, -50);
        assert!(!input.networks[0].known);
        assert_eq!(input.networks[0].hotspot_battery, 0);
    }

    #[test]
    fn decode_of_non_object_is_the_all_off_default() {
        for text in ["[]", "null", "1", "\"x\"", "true"] {
            let input = Input::decode(&json::parse(text).expect("valid"));
            assert_eq!(input, Input::default());
            assert!(!input.power_on);
        }
    }

    #[test]
    fn cell_coercion_only_accepts_one_and_two() {
        assert_eq!(Cell::from_i64(0), Cell::None);
        assert_eq!(Cell::from_i64(1), Cell::FourG);
        assert_eq!(Cell::from_i64(2), Cell::FiveG);
        assert_eq!(Cell::from_i64(3), Cell::None);
        assert_eq!(Cell::from_i64(-7), Cell::None);
    }

    #[test]
    fn encode_is_transient_utf8_without_a_trailing_nul() {
        let output = Output::default().encode();
        // The CString layer appends the NUL; the encoder itself does not.
        assert!(output.ends_with('}'));
        assert!(!output.contains('\0'));
    }
}
