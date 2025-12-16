use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os != "macos" {
        return;
    }

    let bridge_src = PathBuf::from("src/macos/foundation_bridge.swift");
    if !bridge_src.exists() {
        panic!(
            "foundation_bridge.swift missing; expected at {:?}",
            bridge_src
        );
    }

    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR missing"));
    let lib_path = out_dir.join("libfoundation_bridge.dylib");

    let status = Command::new("swiftc")
        .args([
            "-O",
            "-emit-library",
            "-module-name",
            "FoundationBridge",
            bridge_src.to_str().unwrap(),
            "-framework",
            "Foundation",
            "-framework",
            "FoundationModels",
            "-o",
            lib_path.to_str().unwrap(),
        ])
        .status()
        .expect("failed to invoke swiftc");

    if !status.success() {
        panic!(
            "swiftc failed to compile foundation bridge (status: {:?})",
            status
        );
    }

    println!("cargo:rustc-link-search={}", out_dir.display());
    println!("cargo:rustc-link-lib=dylib=foundation_bridge");
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=framework=FoundationModels");
    println!("cargo:rerun-if-changed={}", bridge_src.display());
}
