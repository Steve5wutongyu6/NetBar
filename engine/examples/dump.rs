//! Renders the fixture requested on the command line, or the bundled sample.
//!
//!     cargo run --example dump [path/to/input.json]

fn main() {
    let path = std::env::args().nth(1).unwrap_or_else(|| {
        concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../NetBarTests/Fixtures/sample.json"
        )
        .to_owned()
    });
    let text = std::fs::read_to_string(&path).expect("readable fixture");
    let value = netbar_engine::json::parse(&text).expect("valid fixture JSON");
    let input = netbar_engine::model::Input::decode(&value);
    let output = netbar_engine::menu::build(&input);
    println!("{}", output.encode());
}
