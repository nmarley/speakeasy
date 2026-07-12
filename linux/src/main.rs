fn main() {
    let state = speakeasy_core::app_state_init();
    println!(
        "speakeasy {} (core state={state})",
        env!("CARGO_PKG_VERSION")
    );
}
