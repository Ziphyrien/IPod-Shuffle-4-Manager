use clap::Parser;
use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

mod cli;
mod utils;
mod convert;
mod audio;
mod tts;
mod database;
mod playlist;
mod shuffler;

use cli::Cli;
use utils::check_unicode;
use shuffler::run_shuffler;

static VERBOSE: AtomicBool = AtomicBool::new(false);

macro_rules! vprintln {
    ($($arg:tt)*) => {
        if $crate::VERBOSE.load(::std::sync::atomic::Ordering::Relaxed) {
            println!($($arg)*);
        }
    };
}

// Re-export the macro for use in submodules
pub(crate) use vprintln;

// ─── main ────────────────────────────────────────────────────────────────────

fn main() {
    // Handle Ctrl+C
    ctrlc_handler();

    let cli = Cli::parse();

    if cli.verbose {
        VERBOSE.store(true, Ordering::Relaxed);
    }

    // Validate path
    let path = Path::new(&cli.path);
    if !path.is_dir() {
        eprintln!("寻找 iPod 目录出错。也许它没有连接或挂载？");
        std::process::exit(1);
    }

    // Check write permission by trying to create a temp file
    let test_file = path.join(".ipod_shuffle_write_test");
    match fs::write(&test_file, b"test") {
        Ok(_) => { let _ = fs::remove_file(&test_file); }
        Err(_) => {
            eprintln!("无法获得 iPod 目录的写入权限");
            std::process::exit(1);
        }
    }

    if cli.rename_unicode {
        check_unicode(path);
    }

    println!("iPod Shuffle 4G Manager v{}", env!("CARGO_PKG_VERSION"));
    vprintln!("请求播放列表旁白: {}", cli.playlist_voiceover);
    vprintln!("请求曲目旁白: {}", cli.track_voiceover);

    run_shuffler(&cli);
}

fn ctrlc_handler() {
    let _ = ctrlc::set_handler(|| {
        eprintln!("\n检测到中断，正在退出...");
        std::process::exit(1);
    });
}
