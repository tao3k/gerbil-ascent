//! Installed exec entry for one resident, single-processor Scheme VM.
fn main() {
    let mut args = std::env::args_os().skip(1);
    let path = args.next().expect("private owner socket required");
    let domain = args
        .next()
        .expect("process domain required")
        .to_str()
        .expect("numeric domain")
        .parse()
        .expect("valid process domain");
    assert!(args.next().is_none(), "unexpected owner arguments");
    if let Err(error) = ascent_scheme::serve_process_worker(std::path::Path::new(&path), domain) {
        eprintln!("ASCENT-PROCESS-FAIL {error}");
        std::process::exit(1);
    }
}
