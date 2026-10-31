//! Menu composition: which networks the Wi-Fi menu shows, in what order and
//! with which trailing details. The Apple Wi-Fi menu collapses one ESSID to a
//! single row, floats the joined network, folds weak strangers behind "Other
//! Networks", and lets a Personal Hotspot keep its own section — this module is
//! that policy, expressed once.
//!
//! Nothing here touches CoreWLAN or AppKit, so the whole policy is unit-testable
//! from plain JSON.

use crate::model::{Cell, DetailKind, Input, Item, Network, Output, Peer, Role, Section};

/// Wi-Fi bars shown for a signal strength, 0 through 4 (rule A).
pub fn strength(rssi: i64) -> u8 {
    // 0 means "not measured"; treating it as a reading would draw four bars.
    if rssi >= 0 {
        return 0;
    }
    if rssi >= -60 {
        4
    } else if rssi >= -70 {
        3
    } else if rssi >= -80 {
        2
    } else if rssi >= -88 {
        1
    } else {
        0
    }
}

/// Network rows kept in "Known Networks", joined row included.
pub const MAX_KNOWN: usize = 3;
/// Network rows shown under "Other Networks" before the user unfolds them.
pub const MAX_OTHER: usize = 2;
/// Weakest signal a stranger shows while folded; below this it stays hidden.
pub const RSSI_FLOOR: i64 = -78;
/// Title used for a network macOS did not name.
const REDACTED_TITLE: &str = "Not Nearby";

/// Two names are the same ESSID when they match case-insensitively and after
/// trimming. macOS treats SSIDs as case-sensitive, but a saved profile whose
/// name differs only in case is the same network to the user, and CoreWLAN
/// reports profiles with inconsistent casing.
fn normalize_name(name: &str) -> String {
    name.trim().to_lowercase()
}

/// Builds the full menu for one capture.
pub fn build(input: &Input) -> Output {
    if !input.power_on {
        return Output {
            status_title: Some("Wi-Fi Off".to_owned()),
            // Radio off: no networks, but the switch and the way to Settings stay.
            items: vec![Item::settings_footer()],
            connected_is_hotspot: false,
            ..Output::default()
        };
    }

    let mut output = Output {
        status_title: if input.interface_name.is_none() {
            Some("Wi-Fi Not Available".to_owned())
        } else {
            None
        },
        status_needs_setup: input.interface_name.is_none(),
        ..Output::default()
    };

    // Rule D: one row per ESSID, strongest BSS wins. An entry without a name is
    // only usable when it carries a saved profile name.
    let collapsed = collapse(&input.networks);

    let preferred: Vec<String> = input
        .preferred_networks
        .iter()
        .map(|name| normalize_name(name))
        .collect();
    let is_preferred = |name: &str| preferred.iter().any(|saved| *saved == normalize_name(name));

    // Rule F: the joined record is the strongest record that matches the current
    // SSID, and only it can mark the connection as a Personal Hotspot.
    let joined_record = input
        .current_ssid
        .as_deref()
        .and_then(|ssid| find_record(&collapsed, ssid));
    // The scan record is the primary evidence; the radio's own verdict covers the
    // case where that record could not be identified (names withheld).
    let joined_is_hotspot = joined_record.is_some_and(|record| record.personal_hotspot)
        || input.current_is_personal_hotspot
        // A Continuity report for the joined network's name is evidence too.
        || peer_for(&input.peers, input.current_ssid.as_deref()).is_some();
    output.connected_is_hotspot = joined_is_hotspot;
    output.connected_name = if input.connected_name_redacted {
        None
    } else {
        input.current_ssid.clone()
    };
    output.connected_strength = strength(if input.current_rssi != 0 {
        input.current_rssi
    } else {
        joined_record.map_or(0, |record| record.rssi)
    });
    if let Some(record) = joined_record.filter(|record| record.personal_hotspot) {
        output.connected_cell = Cell::from_i64(record.hotspot_network);
        output.connected_battery = record.hotspot_battery;
    } else if joined_is_hotspot {
        output.connected_cell = Cell::from_i64(input.current_hotspot_network);
        output.connected_battery = input.current_hotspot_battery;
    }
    let connected_peer = peer_for(&input.peers, input.current_ssid.as_deref()).or_else(|| {
        sole_peer(
            &input.peers,
            input,
            collapsed.iter().filter(|n| n.personal_hotspot).count(),
        )
    });
    if let Some(peer) = connected_peer {
        let cell = cell_from_label(peer.network_label.as_deref());
        if cell != Cell::None {
            output.connected_cell = cell;
        }
        if peer.battery_percent > 0 {
            output.connected_battery = peer.battery_percent;
        }
    }

    // Rule E.1: Personal Hotspots get their own section, whether or not they are
    // saved, and always keep their Cellular/Battery detail.
    // Owned clones: the joined hotspot may need a row synthesised below, and a
    // borrowed list could not take one without leaking it.
    let mut hotspots: Vec<Network> = collapsed
        .iter()
        .filter(|network| network.personal_hotspot)
        .cloned()
        .collect();
    // A hotspot can be the joined network while no scan record carries its
    // marker — names withheld, or the access point left the scan. The radio's own
    // verdict still puts it in the section, so it is never missing from the menu.
    let joined_hotspot_row_missing = joined_is_hotspot
        && !hotspots
            .iter()
            .any(|network| match (&network.ssid, &input.current_ssid) {
                (_, None) => true,
                (Some(ssid), Some(current)) => normalize_name(ssid) == normalize_name(current),
                (None, Some(_)) => false,
            });
    if joined_hotspot_row_missing {
        let mut synthetic = Network {
            ssid: input.current_ssid.clone(),
            bssid: None,
            service_name: None,
            rssi: input.current_rssi,
            known: true,
            personal_hotspot: true,
            hotspot_network: input.current_hotspot_network,
            hotspot_battery: input.current_hotspot_battery,
            security: 0,
        };
        if synthetic.hotspot_network == 0 {
            synthetic.hotspot_network = output.connected_cell as i64;
        }
        hotspots.push(synthetic);
    }
    sort_by_signal(&mut hotspots);
    if !hotspots.is_empty() {
        output.items.push(Item::header(
            Section::Hotspot,
            "header.hotspot",
            "Personal Hotspot",
        ));
        for (index, network) in hotspots.iter().enumerate() {
            // A hotspot whose name macOS withheld still earns a row: the beacon
            // says what it is, and the detail columns carry signal, Cellular and
            // battery, which is exactly what the section is for.
            let named = network.ssid.clone();
            let title = named.clone().unwrap_or_else(|| REDACTED_TITLE.to_owned());
            let identity = named.clone().unwrap_or_else(|| {
                // Without an address the scan order is all there is to tell two
                // unnamed hotspots apart, and it only has to be unique per menu.
                match network.identity() {
                    address if address.is_empty() => format!("unnamed-{index}"),
                    address => address,
                }
            });
            let mut item = Item::network(Section::Hotspot, format!("hotspot.{identity}"), &title);
            if named.is_none() {
                item.ssid = None;
                item.redacted = true;
            }
            fill_signal(&mut item, network);
            item.detail_kind = DetailKind::AppleHotspot;
            item.cell = Cell::from_i64(network.hotspot_network);
            item.battery = clamp_battery(network.hotspot_battery);
            item.is_joined = is_joined_name(input, named.as_deref().unwrap_or_default());
            apply_peer(
                &mut item,
                peer_for(&input.peers, named.as_deref())
                    .or_else(|| sole_peer(&input.peers, input, hotspots.len())),
            );
            output.items.push(item);
        }
    }

    // Rule E.2: Known Networks, joined row first, capped. A joined hotspot is
    // already the section above — repeating it here would double the row.
    let mut known_rows: Vec<Item> = Vec::new();
    if input.connected_name_redacted {
        // Rule E.3: the joined network's name is hidden; keep its slot without
        // inventing one. macOS shows whatever neighbour it can still see.
        let mut item = Item::network(Section::Known, "known.redacted".to_owned(), REDACTED_TITLE);
        item.ssid = None;
        item.redacted = true;
        item.is_joined = true;
        item.rssi = input.current_rssi;
        item.strength = strength(input.current_rssi);
        item.security = joined_record.map_or(0, |record| record.security);
        item.detail_kind = if joined_is_hotspot {
            DetailKind::AppleHotspot
        } else if item.security != 0 {
            DetailKind::Lock
        } else {
            DetailKind::None
        };
        known_rows.push(item);
    } else if let Some(ssid) = input.current_ssid.as_deref().filter(|_| !joined_is_hotspot) {
        let record = find_record(&collapsed, ssid);
        let mut item = Item::network(Section::Known, format!("known.{ssid}"), ssid);
        item.is_joined = true;
        item.rssi = if input.current_rssi != 0 {
            input.current_rssi
        } else {
            record.map_or(0, |network| network.rssi)
        };
        item.strength = strength(item.rssi);
        item.security = record.map_or(0, |network| network.security);
        item.detail_kind = if joined_is_hotspot {
            DetailKind::AppleHotspot
        } else if item.security != 0 {
            DetailKind::Lock
        } else {
            DetailKind::None
        };
        if joined_is_hotspot {
            item.cell = Cell::from_i64(record.map_or(0, |network| network.hotspot_network));
            item.battery = clamp_battery(record.map_or(0, |network| network.hotspot_battery));
        }
        known_rows.push(item);
    }

    let mut saved: Vec<&Network> = collapsed
        .iter()
        .filter(|network| !network.personal_hotspot && network.ssid.is_some())
        .filter(|network| network.known || is_preferred(network.ssid.as_deref().unwrap_or("")))
        .filter(|network| !is_joined_name(input, network.ssid.as_deref().unwrap_or("")))
        .collect();
    sort_by_signal(&mut saved);
    for network in saved {
        let ssid = network.ssid.clone().unwrap_or_default();
        let mut item = Item::network(Section::Known, format!("known.{ssid}"), &ssid);
        fill_signal(&mut item, network);
        item.detail_kind = if network.security != 0 {
            DetailKind::Lock
        } else {
            DetailKind::None
        };
        known_rows.push(item);
    }
    // Rows past the cap are dropped entirely: the Wi-Fi menu stays short. An
    // empty section renders no header at all.
    known_rows.truncate(MAX_KNOWN);
    if !known_rows.is_empty() {
        output.items.push(Item::header(
            Section::Known,
            "header.known",
            "Known Networks",
        ));
        output.items.extend(known_rows);
    }

    // Rule E.4: strangers, folded behind a single row unless unfolded.
    let known_ids: Vec<String> = output
        .items
        .iter()
        .filter(|item| item.role == Role::Network && item.section != Section::Other)
        .filter_map(|item| item.ssid.clone().map(|ssid| normalize_name(&ssid)))
        .collect();
    let mut others: Vec<&Network> = collapsed
        .iter()
        .filter(|network| !network.personal_hotspot)
        .filter(|network| match network.ssid.as_deref() {
            // Rows already shown above never repeat down here.
            Some(ssid) => !known_ids.contains(&normalize_name(ssid)),
            None => true,
        })
        .filter(|network| !is_joined_name(input, network.ssid.as_deref().unwrap_or("")))
        .filter(|network| network.ssid.is_some() || redacted_title(network, &preferred).is_some())
        .collect();
    sort_by_signal(&mut others);

    let visible: Vec<&Network> = if input.reveal_other {
        others.clone()
    } else {
        others
            .iter()
            .copied()
            .filter(|network| {
                match &network.ssid {
                    // A named network has to be strong enough to earn a row.
                    Some(_) => network.rssi >= RSSI_FLOOR,
                    // An unnamed one is only here because a saved profile names
                    // it, which makes it worth showing at any strength.
                    None => redacted_title(network, &preferred).is_some() && network.rssi != 0,
                }
            })
            .take(MAX_OTHER)
            .collect()
    };
    output.hidden_other_count = (others.len() - visible.len()) as i64;

    output.items.push(Item::other_aggregator());
    for network in &visible {
        // An unnamed entry can only appear when a saved profile still names it.
        let (title, redacted) = match &network.ssid {
            Some(ssid) => (ssid.clone(), false),
            None => match redacted_title(network, &preferred) {
                Some(title) => (title, true),
                None => continue,
            },
        };
        let identifier = match &network.ssid {
            Some(ssid) => format!("other.{ssid}"),
            None => format!(
                "other.redacted.{}",
                network.service_name.clone().unwrap_or_default()
            ),
        };
        let mut item = Item::network(Section::Other, identifier, &title);
        if redacted {
            item.ssid = None;
            item.redacted = true;
        }
        fill_signal(&mut item, network);
        // A stranger that needs a password shows a lock, same as a saved one.
        item.detail_kind = if network.security != 0 {
            DetailKind::Lock
        } else {
            DetailKind::None
        };
        output.items.push(item);
    }

    // Rule E.5: the system settings row.
    output.items.push(Item::settings_footer());
    output
}

/// A row for a network whose SSID the OS withheld but whose saved profile name
/// is known: macOS still lists it, so NetBar does too, under a neutral title.
fn redacted_title(network: &Network, preferred: &[String]) -> Option<String> {
    if network.ssid.is_some() {
        return None;
    }
    let service = network.service_name.as_deref()?;
    preferred
        .iter()
        .any(|saved| *saved == normalize_name(service))
        .then(|| REDACTED_TITLE.to_owned())
}

fn is_joined_name(input: &Input, ssid: &str) -> bool {
    !input.connected_name_redacted
        && input
            .current_ssid
            .as_deref()
            .is_some_and(|current| normalize_name(current) == normalize_name(ssid))
}

fn find_record<'a>(networks: &'a [Network], ssid: &str) -> Option<&'a Network> {
    networks
        .iter()
        .filter(|network| {
            network
                .ssid
                .as_deref()
                .is_some_and(|name| normalize_name(name) == normalize_name(ssid))
        })
        .max_by_key(|network| network.rssi)
}

fn fill_signal(item: &mut Item, network: &Network) {
    item.rssi = network.rssi;
    item.strength = strength(network.rssi);
    item.security = network.security;
}

fn clamp_battery(percent: i64) -> u8 {
    percent.clamp(0, 100) as u8
}

/// Turns the system's own label into the enum the menu draws.
pub fn cell_from_label(label: Option<&str>) -> Cell {
    match label.map(str::trim) {
        Some(text) if text.eq_ignore_ascii_case("5G") => Cell::FiveG,
        Some(text) if text.eq_ignore_ascii_case("4G") || text.eq_ignore_ascii_case("LTE") => {
            Cell::FourG
        }
        _ => Cell::None,
    }
}

/// The Continuity report for a hotspot, matched to a row by name.
fn peer_for<'a>(peers: &'a [Peer], ssid: Option<&str>) -> Option<&'a Peer> {
    let name = normalize_name(ssid?);
    peers.iter().find(|peer| normalize_name(&peer.name) == name)
}

/// The report for the only hotspot on offer.
///
/// When macOS withholds names nothing can be matched by name, but one joined
/// hotspot plus one reported device is unambiguous, so the pair is used.
fn sole_peer<'a>(peers: &'a [Peer], input: &Input, hotspot_rows: usize) -> Option<&'a Peer> {
    let unnamed = input.connected_name_redacted || input.current_ssid.is_none();
    if unnamed && peers.len() == 1 && hotspot_rows == 1 {
        return peers.first();
    }
    None
}

/// Applies what Continuity knows to a hotspot row: generation, battery and the
/// Cellular bars, none of which the Wi-Fi beacon carries.
fn apply_peer(item: &mut Item, peer: Option<&Peer>) {
    let Some(peer) = peer else { return };
    let cell = cell_from_label(peer.network_label.as_deref());
    if cell != Cell::None {
        item.cell = cell;
    }
    if peer.battery_percent > 0 {
        item.battery = clamp_battery(peer.battery_percent);
    }
    item.cellular_signal = u8::try_from(peer.signal_bars.clamp(0, 4)).unwrap_or(0);
}

impl Network {
    /// A stable identity for a network whose name is unavailable.
    fn identity(&self) -> String {
        self.bssid.clone().unwrap_or_default()
    }
}

/// Strongest first, then by name so equally strong networks never swap places
/// between refreshes.
fn sort_by_signal<T: std::borrow::Borrow<Network>>(networks: &mut [T]) {
    networks.sort_by(|left, right| {
        let (left, right) = (left.borrow(), right.borrow());
        right
            .rssi
            .cmp(&left.rssi)
            .then_with(|| left.ssid.cmp(&right.ssid))
    });
}

/// Rule D: the strongest record per ESSID. Entries with no name at all are kept
/// only when a saved profile still identifies them.
fn collapse(networks: &[Network]) -> Vec<Network> {
    let mut collapsed: Vec<Network> = Vec::with_capacity(networks.len());
    for network in networks {
        // An entry needs something to be identified by: a name, a saved profile
        // that names it, or a hotspot flag. macOS withholds the BSSID along with
        // the name, so a hotspot with neither is still kept: its beacon says what
        // it is, and that is the whole point of the section.
        let has_identity =
            network.ssid.is_some() || network.service_name.is_some() || network.personal_hotspot;
        if !has_identity {
            continue;
        }
        let duplicate = match &network.ssid {
            Some(ssid) => collapsed.iter_mut().find(|existing| {
                existing
                    .ssid
                    .as_deref()
                    .is_some_and(|name| normalize_name(name) == normalize_name(ssid))
            }),
            // Unnamed entries can only be told apart by their address.
            None => collapsed.iter_mut().find(|existing| {
                existing.ssid.is_none()
                    && network.bssid.is_some()
                    && existing.bssid == network.bssid
            }),
        };
        match duplicate {
            Some(existing) if existing.rssi >= network.rssi => {}
            Some(existing) => *existing = network.clone(),
            None => collapsed.push(network.clone()),
        }
    }
    collapsed
}
