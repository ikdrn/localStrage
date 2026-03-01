use serde::Serialize;
use sysinfo::Disks;

/// 各ドライブの情報を保持する構造体
#[derive(Debug, Serialize, Clone)]
pub struct DiskInfo {
    /// ドライブ名 (例: "Local Disk", "SSD")
    pub name: String,
    /// マウントポイント (例: "C:\\", "D:\\")
    pub mount_point: String,
    /// 合計容量 (バイト)
    pub total_space: u64,
    /// 空き容量 (バイト)
    pub available_space: u64,
    /// 使用済み容量 (バイト)
    pub used_space: u64,
    /// 使用率 (0.0〜100.0)
    pub usage_percent: f64,
    /// ファイルシステム種別 (例: "NTFS", "FAT32")
    pub file_system: String,
}

/// Tauri コマンド: 接続されている全ドライブの情報を返す
///
/// アクセス不能なドライブやサイズが 0 のエントリは自動的に除外する。
/// エラーが発生した場合は文字列として返し、フロントエンドでハンドリングする。
#[tauri::command]
fn get_disk_info() -> Result<Vec<DiskInfo>, String> {
    let disks = Disks::new_with_refreshed_list();
    let mut disk_list: Vec<DiskInfo> = Vec::new();

    for disk in disks.list() {
        let total = disk.total_space();

        // 合計容量が 0 のドライブはアクセス不能か仮想ドライブのため除外
        if total == 0 {
            continue;
        }

        let available = disk.available_space();

        // saturating_sub で算術アンダーフローを防止
        let used = total.saturating_sub(available);

        // 使用率を計算し 0.0〜100.0 にクランプ
        let usage_percent = ((used as f64 / total as f64) * 100.0).clamp(0.0, 100.0);

        // OsStr -> String 変換 (非 UTF-8 文字はロスレス変換)
        let raw_name = disk.name().to_string_lossy().into_owned();
        let name = if raw_name.trim().is_empty() {
            "ローカルディスク".to_string()
        } else {
            raw_name
        };

        let mount_point = disk.mount_point().to_string_lossy().into_owned();
        let file_system = disk.file_system().to_string_lossy().into_owned();

        disk_list.push(DiskInfo {
            name,
            mount_point,
            total_space: total,
            available_space: available,
            used_space: used,
            usage_percent,
            file_system,
        });
    }

    Ok(disk_list)
}

/// アプリのエントリーポイント (main.rs から呼ばれる)
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![get_disk_info])
        .run(tauri::generate_context!())
        .expect("error while running tauri application")
}
