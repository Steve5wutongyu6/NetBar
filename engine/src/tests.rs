//! Behaviour tests for the menu policy. Every rule in the contract has at least
//! one case here, and the two fixtures are asserted end to end.

use crate::json;
use crate::menu::{self, MAX_KNOWN, MAX_OTHER};
use crate::model::{Cell, DetailKind, Input, Item, Output, Role, Section};

const SAMPLE: &str = include_str!("../../NetBarTests/Fixtures/sample.json");
const REDACTED: &str = include_str!("../../NetBarTests/Fixtures/redacted.json");

/// Decodes a request and renders its menu, as the FFI entry point does.
fn render(request: &str) -> Output {
    let value = json::parse(request).expect("test fixtures are valid JSON");
    menu::build(&Input::decode(&value))
}

/// Convenience: the request shape used by the simple tests.
fn request(power_on: bool, current: Option<&str>, networks: &str) -> String {
    let current = match current {
        Some(name) => format!("\"{name}\""),
        None => "null".to_owned(),
    };
    format!(
        "{{\"schemaVersion\":1,\"powerOn\":{power_on},\"currentSSID\":{current},\
\"connectedNameRedacted\":false,\"interfaceName\":\"en0\",\"currentRSSI\":-50,\
\"scanning\":true,\"preferredNetworks\":[],\"revealOther\":false,\"networks\":[{networks}]}}"
    )
}

fn network(ssid: &str, rssi: i64, extra: &str) -> String {
    format!(
        "{{\"ssid\":\"{ssid}\",\"rssi\":{rssi},\"known\":false,\"personalHotspot\":false,\
\"hotspotNetwork\":0,\"hotspotBattery\":0,\"security\":3{extra}}}"
    )
}

fn titles(output: &Output) -> Vec<String> {
    output
        .items
        .iter()
        .map(|item| item.title.clone().unwrap_or_default())
        .collect()
}

fn rows(output: &Output, section: Section) -> Vec<&Item> {
    output
        .items
        .iter()
        .filter(|item| item.section == section && item.role == Role::Network)
        .collect()
}

fn ids(output: &Output) -> Vec<String> {
    output.items.iter().map(|item| item.id.clone()).collect()
}

// Rules A: bars.
#[test]
fn strength_boundaries_cover_every_bar_count() {
    assert_eq!(menu::strength(-30), 4);
    assert_eq!(menu::strength(-60), 4);
    assert_eq!(menu::strength(-61), 3);
    assert_eq!(menu::strength(-70), 3);
    assert_eq!(menu::strength(-71), 2);
    assert_eq!(menu::strength(-80), 2);
    assert_eq!(menu::strength(-81), 1);
    assert_eq!(menu::strength(-88), 1);
    assert_eq!(menu::strength(-89), 0);
    assert_eq!(menu::strength(-127), 0);
}

// Rule B: radio off.
#[test]
fn power_off_yields_no_network_rows() {
    let output = render(&request(false, None, &network("Home", -50, "")));
    assert_eq!(output.status_title.as_deref(), Some("Wi-Fi Off"));
    assert_eq!(ids(&output), ["footer.settings"]);
    assert_eq!(output.hidden_other_count, 0);
    assert!(!output.connected_is_hotspot);
    assert_eq!(output.connected_strength, 0);
}

// Rule B applies even when the rest of the request looks healthy.
#[test]
fn power_off_wins_over_a_full_scan() {
    let full = render(&request(true, Some("Home"), &network("Home", -40, "")));
    let off = render(&request(false, Some("Home"), &network("Home", -40, "")));
    assert!(full.items.len() > off.items.len());
    assert_eq!(ids(&off), ["footer.settings"]);
}

// Rule C: no radio at all.
#[test]
fn missing_interface_reports_not_available() {
    let text = request(true, None, "").replace("\"en0\"", "null");
    let output = render(&text);
    assert_eq!(output.status_title.as_deref(), Some("Wi-Fi Not Available"));
    assert!(output.status_needs_setup);
}

// Rule D: one row per ESSID, strongest wins.
#[test]
fn duplicate_essids_collapse_to_the_strongest_bss() {
    let text = request(
        true,
        None,
        &format!("{},{}", network("Cafe", -80, ""), network("Cafe", -55, "")),
    );
    let output = render(&text);
    let others = rows(&output, Section::Other);
    assert_eq!(others.len(), 1);
    assert_eq!(others[0].rssi, -55);
    assert_eq!(others[0].strength, 4);
}

// Rule D: entries without a name and without a profile are dropped.
#[test]
fn anonymous_networks_are_ignored() {
    let text = request(
        true,
        None,
        "{\"ssid\":null,\"rssi\":-50,\"known\":false,\"personalHotspot\":false,\
\"hotspotNetwork\":0,\"hotspotBattery\":0}",
    );
    let output = render(&text);
    assert!(rows(&output, Section::Other).is_empty());
    assert_eq!(output.hidden_other_count, 0);
}

// Rule E.1: hotspot section, its header, and its detail.
#[test]
fn personal_hotspot_gets_its_own_section() {
    let text = request(
        true,
        None,
        &network(
            "Phone",
            -58,
            ",\"personalHotspot\":true,\"hotspotNetwork\":2,\"hotspotBattery\":72",
        ),
    );
    let output = render(&text);
    assert_eq!(output.items[0].id, "header.hotspot");
    assert_eq!(output.items[0].title.as_deref(), Some("Personal Hotspot"));
    let hotspot = rows(&output, Section::Hotspot);
    assert_eq!(hotspot.len(), 1);
    assert_eq!(hotspot[0].detail_kind, DetailKind::AppleHotspot);
    assert_eq!(hotspot[0].cell, Cell::FiveG);
    assert_eq!(hotspot[0].battery, 72);
    assert_eq!(hotspot[0].strength, 4);
}

// Rule E.1: the header only exists when a hotspot does.
#[test]
fn hotspot_header_is_absent_without_a_hotspot() {
    let output = render(&request(true, None, &network("Cafe", -50, "")));
    assert!(!ids(&output).contains(&"header.hotspot".to_owned()));
}

// Rule E.1: unknown Cellular data still renders the hotspot detail.
#[test]
fn hotspot_without_cellular_metadata_still_uses_the_hotspot_detail() {
    let text = request(
        true,
        None,
        &network("Phone", -58, ",\"personalHotspot\":true"),
    );
    let output = render(&text);
    let hotspot = rows(&output, Section::Hotspot);
    assert_eq!(hotspot[0].detail_kind, DetailKind::AppleHotspot);
    assert_eq!(hotspot[0].cell, Cell::None);
    assert_eq!(hotspot[0].battery, 0);
}

// Rule F: a joined hotspot is not repeated as a Known row.
#[test]
fn joined_hotspot_appears_once() {
    let text = request(
        true,
        Some("Phone"),
        &network(
            "Phone",
            -52,
            ",\"personalHotspot\":true,\"hotspotNetwork\":1,\"hotspotBattery\":40",
        ),
    );
    let output = render(&text);
    assert!(output.connected_is_hotspot);
    assert_eq!(output.connected_cell, Cell::FourG);
    assert_eq!(output.connected_battery, 40);
    assert_eq!(output.connected_strength, 4);
    let hotspots = rows(&output, Section::Hotspot);
    assert_eq!(hotspots.len(), 1);
    assert!(hotspots[0].is_joined);
    assert!(rows(&output, Section::Known).is_empty());
}

// Rule E.2: the joined network leads the Known section, and keeps its bars.
#[test]
fn joined_network_leads_known_and_reports_its_signal() {
    let text = request(
        true,
        Some("Home"),
        &format!("{},{}", network("Home", -71, ""), network("Cafe", -50, "")),
    );
    let output = render(&text);
    let known = rows(&output, Section::Known);
    assert_eq!(known.len(), 1);
    assert_eq!(known[0].ssid.as_deref(), Some("Home"));
    assert!(known[0].is_joined);
    // The interface reading (-50) is authoritative; bars follow from it.
    assert_eq!(known[0].rssi, -50);
    assert_eq!(known[0].strength, 4);
    assert_eq!(known[0].detail_kind, DetailKind::Lock);
}

// Rule E.2: the joined network shows even when the scan missed it.
#[test]
fn joined_network_is_created_when_the_scan_omits_it() {
    let text = request(true, Some("Elsewhere"), &network("Cafe", -50, ""));
    let output = render(&text);
    let known = rows(&output, Section::Known);
    assert_eq!(known[0].ssid.as_deref(), Some("Elsewhere"));
    assert_eq!(known[0].id, "known.Elsewhere");
    assert!(known[0].is_joined);
}

// Rule E.2: saved networks are ranked by signal and capped.
#[test]
fn known_section_is_capped() {
    let mut entries = Vec::new();
    for (index, rssi) in [-40, -50, -60, -70, -80].iter().enumerate() {
        entries.push(network(&format!("Saved{index}"), *rssi, ",\"known\":true"));
    }
    let output = render(&request(true, None, &entries.join(",")));
    let known = rows(&output, Section::Known);
    assert_eq!(known.len(), MAX_KNOWN);
    assert_eq!(known[0].ssid.as_deref(), Some("Saved0"));
    assert_eq!(known[2].ssid.as_deref(), Some("Saved2"));
}

// R0: a saved-profile name marks a network as known even without the flag.
#[test]
fn preferred_profile_names_mark_networks_known() {
    let text = request(true, None, &network("Cafe", -50, "")).replace(
        "\"preferredNetworks\":[]",
        "\"preferredNetworks\":[\"cafe\"]",
    );
    let output = render(&text);
    assert_eq!(rows(&output, Section::Known).len(), 1);
    assert!(rows(&output, Section::Other).len() <= MAX_OTHER);
}

// Rule E.3: a hidden connection keeps its slot without inventing a name.
#[test]
fn redacted_connection_keeps_an_anonymous_joined_row() {
    let text = request(true, None, &network("Cafe", -50, ""))
        .replace(
            "\"connectedNameRedacted\":false",
            "\"connectedNameRedacted\":true",
        )
        .replace("\"currentRSSI\":-50", "\"currentRSSI\":-63");
    let output = render(&text);
    let known = rows(&output, Section::Known);
    assert_eq!(known[0].id, "known.redacted");
    assert_eq!(known[0].title.as_deref(), Some("Not Nearby"));
    assert!(known[0].redacted);
    assert!(known[0].is_joined);
    assert_eq!(known[0].strength, 3);
    assert_eq!(output.connected_name, None);
}

// Rule E.4: strangers are folded, the row is always there.
#[test]
fn other_networks_are_folded_and_counted() {
    let entries: Vec<String> = (0..5)
        .map(|index| network(&format!("Guest{index}"), -40 - index * 5, ""))
        .collect();
    let output = render(&request(true, None, &entries.join(",")));
    let row = output
        .items
        .iter()
        .position(|item| item.role == Role::OtherNetworks)
        .expect("the Other Networks row is always present");
    assert!(output.items[row].title.as_deref() == Some("Other Networks"));
    assert_eq!(rows(&output, Section::Other).len(), MAX_OTHER);
    assert_eq!(output.hidden_other_count, 3);
}

// Rule E.4: weak strangers are hidden while folded.
#[test]
fn weak_networks_are_hidden_while_folded() {
    let entries = [network("Near", -50, ""), network("Far", -95, "")].join(",");
    let output = render(&request(true, None, &entries));
    assert!(!titles(&output).contains(&"Far".to_owned()));
    assert_eq!(output.hidden_other_count, 1);
}

// Rule E.4: a secured stranger keeps its lock badge.
#[test]
fn strangers_show_a_lock_when_they_need_a_password() {
    let locked = network("Cafe", -50, ",\"security\":3");
    let open = network("Park", -55, ",\"security\":0");
    let output = render(&request(true, None, &format!("{locked},{open}")));
    let others = rows(&output, Section::Other);
    assert_eq!(others[0].detail_kind, DetailKind::Lock);
    assert_eq!(others[1].detail_kind, DetailKind::None);
}

// A hotspot whose name macOS withheld still gets its row, with its detail.
#[test]
fn unnamed_hotspot_still_appears_with_its_detail() {
    let entries = "{\"ssid\":null,\"bssid\":\"AA:BB:CC:00:11:22\",\"rssi\":-61,\"known\":false,\
\"personalHotspot\":true,\"hotspotNetwork\":2,\"hotspotBattery\":88}";
    let output = render(&request(true, None, entries));
    let hotspot = rows(&output, Section::Hotspot);
    assert_eq!(hotspot.len(), 1);
    assert_eq!(hotspot[0].title.as_deref(), Some("Not Nearby"));
    assert!(hotspot[0].redacted);
    assert_eq!(hotspot[0].id, "hotspot.AA:BB:CC:00:11:22");
    assert_eq!(hotspot[0].cell, Cell::FiveG);
    assert_eq!(hotspot[0].battery, 88);
    assert_eq!(hotspot[0].strength, 3);
}

// macOS withholds the BSSID along with the name, so a hotspot can arrive with
// neither; it still belongs in the section, with a unique row id.
#[test]
fn unnamed_hotspot_without_an_address_is_kept() {
    let entries = "{\"ssid\":null,\"rssi\":-61,\"known\":false,\"personalHotspot\":true,\
\"hotspotNetwork\":2,\"hotspotBattery\":88}";
    let output = render(&request(true, None, entries));
    let hotspot = rows(&output, Section::Hotspot);
    assert_eq!(hotspot.len(), 1);
    assert_eq!(hotspot[0].title.as_deref(), Some("Not Nearby"));
    assert!(hotspot[0].redacted);
    assert_eq!(hotspot[0].battery, 88);
}

// Two address-less hotspots still get two distinct rows.
#[test]
fn addressless_hotspots_have_unique_ids() {
    let one = "{\"ssid\":null,\"rssi\":-61,\"known\":false,\"personalHotspot\":true,\"hotspotNetwork\":2}";
    let two = "{\"ssid\":null,\"rssi\":-55,\"known\":false,\"personalHotspot\":true,\"hotspotNetwork\":2}";
    let output = render(&request(true, None, &format!("{one},{two}")));
    let hotspot = rows(&output, Section::Hotspot);
    assert_eq!(hotspot.len(), 2);
    assert_ne!(hotspot[0].id, hotspot[1].id);
}

// Two unnamed hotspots stay two rows: they are told apart by address.
#[test]
fn unnamed_hotspots_are_deduplicated_by_address() {
    let one = "{\"ssid\":null,\"bssid\":\"AA:00\",\"rssi\":-61,\"known\":false,\"personalHotspot\":true,\"hotspotNetwork\":2}";
    let same = "{\"ssid\":null,\"bssid\":\"AA:00\",\"rssi\":-70,\"known\":false,\"personalHotspot\":true,\"hotspotNetwork\":2}";
    let other = "{\"ssid\":null,\"bssid\":\"BB:00\",\"rssi\":-65,\"known\":false,\"personalHotspot\":true,\"hotspotNetwork\":2}";
    let output = render(&request(true, None, &format!("{one},{same},{other}")));
    let hotspot = rows(&output, Section::Hotspot);
    assert_eq!(hotspot.len(), 2);
    assert_eq!(hotspot[0].rssi, -61);
}

// revealOther: unfolding shows everything and clears the counter.
#[test]
fn unfolding_reveals_every_network() {
    let entries: Vec<String> = (0..6)
        .map(|index| network(&format!("Guest{index}"), -40 - index * 8, ""))
        .collect();
    let text = request(true, None, &entries.join(","))
        .replace("\"revealOther\":false", "\"revealOther\":true");
    let output = render(&text);
    assert_eq!(rows(&output, Section::Other).len(), 6);
    assert_eq!(output.hidden_other_count, 0);
}

// R1: a redacted SSID with a saved profile still gets a row.
#[test]
fn redacted_network_with_a_saved_profile_is_listed() {
    let entries = "{\"ssid\":null,\"rssi\":-55,\"known\":false,\"personalHotspot\":false,\
\"hotspotNetwork\":0,\"hotspotBattery\":0,\"serviceName\":\"Office\"}";
    let text = request(true, None, entries).replace(
        "\"preferredNetworks\":[]",
        "\"preferredNetworks\":[\"Office\"]",
    );
    let output = render(&text);
    let others = rows(&output, Section::Other);
    assert_eq!(others.len(), 1);
    assert_eq!(others[0].title.as_deref(), Some("Not Nearby"));
    assert!(others[0].redacted);
    assert_eq!(others[0].id, "other.redacted.Office");
}

// R1: the same entry without a saved profile stays invisible.
#[test]
fn redacted_network_without_a_profile_is_ignored() {
    let entries = "{\"ssid\":null,\"rssi\":-55,\"known\":false,\"personalHotspot\":false,\
\"hotspotNetwork\":0,\"hotspotBattery\":0,\"serviceName\":\"Office\"}";
    let output = render(&request(true, None, entries));
    assert!(rows(&output, Section::Other).is_empty());
}

// Rule E.5: the settings row is last and spelled with an ellipsis.
#[test]
fn settings_row_is_the_last_item() {
    let output = render(&request(true, None, &network("Cafe", -50, "")));
    let last = output.items.last().expect("a menu is never empty when on");
    assert_eq!(last.role, Role::Settings);
    assert_eq!(last.id, "footer.settings");
    assert_eq!(last.title.as_deref(), Some("Wi-Fi Settings\u{2026}"));
}

// Rule G: equal signal falls back to the name, deterministically.
#[test]
fn equal_signals_order_by_name() {
    let entries = [network("beta", -50, ""), network("Alpha", -50, "")].join(",");
    let output = render(&request(true, None, &entries));
    let others = rows(&output, Section::Other);
    assert_eq!(others[0].ssid.as_deref(), Some("Alpha"));
    assert_eq!(others[1].ssid.as_deref(), Some("beta"));
}

// Rule H: junk in, empty menu out, and never a panic.
#[test]
fn malformed_requests_return_the_empty_menu() {
    for text in ["", "{", "[]", "null", "\"x\"", "{\"powerOn\":true,"] {
        let output = match json::parse(text) {
            Ok(value) => menu::build(&Input::decode(&value)),
            Err(_) => Output {
                status_title: None,
                ..Output::default()
            },
        };
        assert!(
            rows(&output, Section::Hotspot).is_empty()
                && rows(&output, Section::Known).is_empty()
                && rows(&output, Section::Other).is_empty(),
            "unexpected rows for {text:?}"
        );
    }
}

#[test]
fn unknown_fields_are_tolerated() {
    let text = request(true, None, &network("Cafe", -50, "")).replace(
        "\"scanning\":true",
        "\"scanning\":true,\"future\":{\"a\":[1,2,3]}",
    );
    let output = render(&text);
    assert_eq!(rows(&output, Section::Other).len(), 1);
}

// Rule I: names with quotes, emoji and CJK survive the round trip.
#[test]
fn awkward_names_survive_encoding() {
    let names = [
        "A\"quoted\"Net",
        "back\\slash",
        "吴同宇的iPhone",
        "café ☕️",
        "tab\there",
    ];
    let entries: Vec<String> = names
        .iter()
        .enumerate()
        .map(|(index, name)| {
            let escaped = json_escape(name);
            format!(
                "{{\"ssid\":{escaped},\"rssi\":{},\"known\":true,\"personalHotspot\":false,\
\"hotspotNetwork\":0,\"hotspotBattery\":0}}",
                -40 - index as i64
            )
        })
        .collect();
    let output = render(&request(true, None, &entries.join(",")));
    let encoded = output.encode();
    let decoded = json::parse(&encoded).expect("our own output is valid JSON");
    let titles: Vec<String> = decoded
        .get("items")
        .and_then(|items| items.as_array())
        .expect("items array")
        .iter()
        .filter_map(|item| item.get("title").and_then(|title| title.as_str()))
        .map(str::to_owned)
        .collect();
    for name in names {
        assert!(
            titles.contains(&name.to_owned()),
            "missing {name:?} in {titles:?}"
        );
    }
}

/// Escapes a test name the same way the encoder would.
fn json_escape(text: &str) -> String {
    let mut out = String::new();
    json::write_string(&mut out, text);
    out
}

// Fixture: a normal capture with a joined iPhone hotspot.
#[test]
fn sample_fixture_renders_the_expected_menu() {
    let output = render(SAMPLE);
    assert_eq!(output.status_title, None);
    assert!(!output.status_needs_setup);
    assert!(output.connected_is_hotspot);
    assert_eq!(output.connected_cell, Cell::FourG);
    assert_eq!(output.connected_battery, 64);
    assert_eq!(output.connected_strength, 4);

    assert_eq!(
        ids(&output),
        [
            "header.hotspot",
            "hotspot.吴同宇的iPhone",
            "header.known",
            "known.自习室 3",
            "known.自习室 2",
            "other.row",
            "other.Test&Co",
            "other.A\"quoted\"Net",
            "footer.settings",
        ]
    );
    assert_eq!(output.hidden_other_count, 3);

    let hotspot = rows(&output, Section::Hotspot);
    assert_eq!(hotspot[0].detail_kind, DetailKind::AppleHotspot);
    assert!(hotspot[0].is_joined);
    assert_eq!(hotspot[0].battery, 64);
    assert_eq!(rows(&output, Section::Known).len(), 2);
    assert_eq!(rows(&output, Section::Other).len(), MAX_OTHER);
}

// Fixture: names withheld by the OS.
#[test]
fn redacted_fixture_keeps_a_joined_slot() {
    let output = render(REDACTED);
    assert_eq!(output.connected_name, None);
    let known = rows(&output, Section::Known);
    assert_eq!(known[0].id, "known.redacted");
    assert!(known[0].is_joined);
    assert!(known[0].redacted);
    assert_eq!(known.len(), 2, "the redacted row plus 自习室 3");

    let hotspots = rows(&output, Section::Hotspot);
    assert_eq!(hotspots[0].cell, Cell::FiveG);
    assert_eq!(hotspots[0].battery, 38);
    assert!(
        !output.connected_is_hotspot,
        "a hidden name cannot be matched to a hotspot"
    );
}

// The wire output always carries every key the app decodes.
#[test]
fn encoded_output_has_every_contract_key() {
    let encoded = render(SAMPLE).encode();
    for key in [
        "schemaVersion",
        "statusTitle",
        "statusNeedsSetup",
        "items",
        "hiddenOtherCount",
        "connectedName",
        "connectedIsHotspot",
        "connectedCell",
        "connectedBattery",
        "connectedStrength",
    ] {
        assert!(encoded.contains(&format!("\"{key}\":")), "missing {key}");
    }
    for key in [
        "role",
        "section",
        "id",
        "title",
        "ssid",
        "security",
        "rssi",
        "isJoined",
        "detailKind",
        "cell",
        "battery",
        "strength",
        "redacted",
    ] {
        assert!(
            encoded.contains(&format!("\"{key}\":")),
            "missing item key {key}"
        );
    }
}

// A joined hotspot never renders "Not Nearby" as well.
#[test]
fn redaction_and_hotspot_do_not_both_produce_a_joined_row() {
    let text = request(
        true,
        None,
        &network("Phone", -52, ",\"personalHotspot\":true"),
    )
    .replace(
        "\"connectedNameRedacted\":false",
        "\"connectedNameRedacted\":true",
    )
    .replace("\"currentSSID\":null", "\"currentSSID\":\"Phone\"");
    let output = render(&text);
    let joined: Vec<&Item> = output.items.iter().filter(|item| item.is_joined).collect();
    assert_eq!(joined.len(), 1);
    assert_eq!(joined[0].id, "known.redacted");
}
