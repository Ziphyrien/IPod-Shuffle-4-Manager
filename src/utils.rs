use md5::{Digest, Md5};
use std::fs;
use std::path::Path;

use crate::cli::{AUDIO_EXT, LIST_EXT};

/// 判断 `path` 是否是 `parent` 的子路径
pub fn is_subpath(path: &Path, parent: &Path) -> bool {
    match (fs::canonicalize(path), fs::canonicalize(parent)) {
        (Ok(p), Ok(par)) => p.starts_with(&par),
        _ => {
            // fallback without canonicalize for paths that don't exist yet
            let p = path.to_string_lossy().to_lowercase();
            let par = parent.to_string_lossy().to_lowercase();
            p.starts_with(&par)
        }
    }
}

pub fn raises_unicode_error(s: &str) -> bool {
    s.bytes().any(|b| b > 127)
}

pub fn hash_error_unicode(item: &str) -> String {
    let mut hasher = Md5::new();
    hasher.update(item.as_bytes());
    let digest = hasher.finalize();
    let hex = format!("{:032x}", u128::from_be_bytes(digest.into()));
    // Python: "".join(["{0:02X}".format(ord(x)) for x in reversed(hashlib.md5(...).hexdigest()[:8])])
    // Take first 8 chars of hex, reverse char order, then uppercase each char's ord as 2-digit hex
    let first8: Vec<char> = hex[..8].chars().collect();
    first8.iter().rev().map(|c| format!("{:02X}", *c as u32)).collect()
}

pub fn validate_unicode(path: &str) -> String {
    let parts: Vec<&str> = path.split('/').collect();
    let mut result_parts: Vec<String> = Vec::new();
    let mut last_raise = false;
    for part in &parts {
        if raises_unicode_error(part) {
            result_parts.push(hash_error_unicode(part));
            last_raise = true;
        } else {
            result_parts.push(part.to_string());
            last_raise = false;
        }
    }
    let joined = result_parts.join("/");
    if last_raise {
        if let Some(dot_pos) = path.rfind('.') {
            let ext = path[dot_pos..].to_lowercase();
            if AUDIO_EXT.contains(&ext.as_str()) {
                return format!("{}{}", joined, ext);
            }
        }
    }
    joined
}

pub fn check_unicode(path: &Path) -> bool {
    let mut ret_flag = false;
    let entries = match fs::read_dir(path) {
        Ok(e) => e,
        Err(_) => return false,
    };
    for entry in entries.flatten() {
        let item_path = entry.path();
        let item_name = entry.file_name().to_string_lossy().to_string();
        if item_path.is_file() {
            if let Some(ext) = item_path.extension() {
                let ext_lower = format!(".{}", ext.to_string_lossy().to_lowercase());
                if AUDIO_EXT.contains(&ext_lower.as_str()) || LIST_EXT.contains(&ext_lower.as_str()) {
                    ret_flag = true;
                    if raises_unicode_error(&item_name) {
                        let dest_name = format!("{}{}", hash_error_unicode(&item_name), ext_lower);
                        let dest = path.join(&dest_name);
                        println!("重命名 {} -> {}", item_path.display(), dest.display());
                        if let Err(e) = fs::rename(&item_path, &dest) {
                            eprintln!("重命名失败: {} -> {}: {}", item_path.display(), dest.display(), e);
                        }
                    }
                }
            }
        } else if item_path.is_dir() {
            let sub = check_unicode(&item_path);
            ret_flag = sub || ret_flag;
            if ret_flag && raises_unicode_error(&item_name) {
                let new_name = hash_error_unicode(&item_name);
                let dest = path.join(&new_name);
                println!("重命名 {} -> {}", item_path.display(), dest.display());
                if let Err(e) = fs::rename(&item_path, &dest) {
                    eprintln!("重命名失败: {} -> {}: {}", item_path.display(), dest.display(), e);
                }
            }
        }
    }
    ret_flag
}

/// 将文件的绝对路径转化为 iPod 的相对路径格式
pub fn path_to_ipod(filename: &Path, base: &Path) -> Result<String, String> {
    let abs = fs::canonicalize(filename).unwrap_or_else(|_| filename.to_path_buf());
    let base_abs = fs::canonicalize(base).unwrap_or_else(|_| base.to_path_buf());
    if !abs.starts_with(&base_abs) {
        return Err("Cannot get iPod filename, since file is outside the iPod path".into());
    }
    let rel = abs.strip_prefix(&base_abs).unwrap();
    let ipod_path = format!("/{}", rel.to_string_lossy().replace('\\', "/"));
    Ok(ipod_path)
}

/// 获取路径的小写扩展名（带点号），如 `.mp3`
pub fn ext_lower(p: &Path) -> String {
    p.extension()
        .map(|e| format!(".{}", e.to_string_lossy().to_lowercase()))
        .unwrap_or_default()
}
