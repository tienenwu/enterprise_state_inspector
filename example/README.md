# Enterprise State Inspector example

This Flutter example showcases the overlay, observers, and the optional
WebSocket companion that mirrors timeline events to your desktop console.

## Running the companion

1. 在專案根目錄啟動伴侶程式，並綁定在所有網卡上，讓同 Wi-Fi 的裝置可連線：
   ```sh
   dart run tool/timeline_companion.dart 8787 0.0.0.0
   ```
   > 只執行 `dart run tool/timeline_companion.dart` 會僅聆聽 127.0.0.1，手機或其他電腦將無法連線。

2. 執行此範例 App（真機或模擬器）。

3. 在介面底部的 **Inspector extras** 區塊輸入伴侶的 WebSocket URL，例如：
   - `ws://192.168.0.12:8787/timeline`（同區網主機的 IPv4）
   - Emulator 若要連線宿主，可使用路由器分配的實際 IP。

4. 點選 **Connect companion**，即可在終端看到即時的 timeline 事件、清除動作與匯入通知。

## 其他操作

- 使用 Riverpod 與 Bloc 的示例按鈕觸發狀態更新，觀察 overlay 與 companion 主控台的輸出。
- 試著新增註解、附件或開啟進階篩選，了解 overlay 的完整功能。
- 點選 **Attach placeholder screenshot** 會建立示範附件（例如 `1.jpg`, `2.jpg`, `3.png`），在詳情面板中的 *Attachments* 區塊可以看到描述與連結，展示如何把實際截圖或錄影掛在事件上。

如需更多說明，請參考根目錄的 `README.md`。
