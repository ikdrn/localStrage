import { invoke } from "@tauri-apps/api/core";

// バイト数を人間が読みやすい形式に変換
function formatBytes(bytes) {
  if (bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}

// 使用率に応じたカラークラスを返す
function getUsageClass(percent) {
  if (percent >= 90) return "critical";
  if (percent >= 70) return "warning";
  return "normal";
}

// ディスク情報をカードとして描画
function renderDisks(disks) {
  const container = document.getElementById("disk-list");
  if (!disks || disks.length === 0) {
    container.innerHTML = '<p class="error">ドライブが見つかりませんでした。</p>';
    return;
  }

  container.innerHTML = disks
    .map((disk) => {
      const usageClass = getUsageClass(disk.usage_percent);
      const percent = disk.usage_percent.toFixed(1);
      return `
        <div class="disk-card">
          <div class="disk-header">
            <div class="disk-name">
              <span class="disk-icon">&#128190;</span>
              <span class="mount-point">${disk.mount_point}</span>
              <span class="disk-label">${disk.name || "ローカルディスク"}</span>
              <span class="fs-badge">${disk.file_system}</span>
            </div>
            <div class="disk-percent ${usageClass}">${percent}%</div>
          </div>
          <div class="progress-bar-container">
            <div class="progress-bar ${usageClass}" style="width: ${Math.min(Number(percent), 100)}%"></div>
          </div>
          <div class="disk-stats">
            <div class="stat">
              <span class="stat-label">使用中</span>
              <span class="stat-value">${formatBytes(disk.used_space)}</span>
            </div>
            <div class="stat">
              <span class="stat-label">空き容量</span>
              <span class="stat-value">${formatBytes(disk.available_space)}</span>
            </div>
            <div class="stat">
              <span class="stat-label">合計</span>
              <span class="stat-value">${formatBytes(disk.total_space)}</span>
            </div>
          </div>
        </div>
      `;
    })
    .join("");
}

// ドライブ情報を取得して描画
async function loadDiskInfo() {
  const container = document.getElementById("disk-list");
  container.innerHTML = `
    <div class="loading">
      <div class="spinner"></div>
      <p>ドライブ情報を取得中...</p>
    </div>
  `;

  try {
    const disks = await invoke("get_disk_info");
    renderDisks(disks);
    const now = new Date().toLocaleTimeString("ja-JP");
    document.getElementById("last-updated").textContent = `最終更新: ${now}`;
  } catch (error) {
    container.innerHTML = `<p class="error">エラーが発生しました: ${error}</p>`;
    console.error("Failed to get disk info:", error);
  }
}

// 更新ボタン
document.getElementById("refresh-btn").addEventListener("click", loadDiskInfo);

// 初回ロード
loadDiskInfo();
