# netbar_engine

Menu policy for NetBar, compiled into the app as a static library. The app
captures the radio with CoreWLAN, sends one JSON request, and renders the rows
it gets back. Keeping the policy here means it is testable without a radio.

## Interface

```c
const char *netbar_node_json(const char *input_json); // NBEngineInput JSON in
const char *netbar_engine_version(void);              // static, do not free
void netbar_string_free(char *buffer);                // free a reply
```

`Contracts/NBEngineExports.h` and `Contracts/NBNodeJSON.h` are the ABI.

## Request

`schemaVersion`, `powerOn`, `currentSSID`, `connectedNameRedacted`,
`interfaceName`, `currentRSSI`, `scanning`, `revealOther`, `preferredNetworks`,
`networks[]` (`ssid`, `serviceName`, `rssi`, `known`, `personalHotspot`,
`hotspotNetwork`, `hotspotBattery`, `security`).

## Reply

`statusTitle`, `statusNeedsSetup`, `items[]`, `hiddenOtherCount`,
`connectedName`, `connectedIsHotspot`, `connectedCell`, `connectedBattery`,
`connectedStrength`. Each item carries `role`, `section`, `id`, `title`,
`ssid`, `security`, `rssi`, `isJoined`, `detailKind`, `cell`, `battery`,
`strength`, `redacted`. Missing fields decode to their zero value; malformed
input returns an empty menu rather than failing.

## Rules

Strength is 4 bars at −60 dBm or better, then −70, −80, −88, then 0. Personal
hotspots get their own section and always keep their Cellular and battery
detail. The joined network leads **Known Networks** unless it is a hotspot,
which is listed once in its own section. Three known rows, then two strangers
above −78 dBm; the rest collapse behind **Other Networks** and are counted in
`hiddenOtherCount` until `revealOther` unfolds them.

## Development

```sh
cargo test
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo run --example dump            # renders NetBarTests/Fixtures/sample.json
```
