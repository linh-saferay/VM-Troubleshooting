# Manual: Phát hiện thiết bị "Skylog" mất kết nối quá 15 phút

Tài liệu giải thích chi tiết luồng phát hiện thiết bị nhóm "Skylog" bị mất kết
nối liên tục quá 15 phút, dùng để sinh cảnh báo mức độ nghiêm trọng cao hơn
(khác với cảnh báo Disconnected/Connected thông thường của NetAlertX).

## Mục lục

- [Ý tưởng tổng quan](#ý-tưởng-tổng-quan)
- [Sơ đồ luồng](#sơ-đồ-luồng)
- [Cấu trúc dữ liệu: `Ina_dev_list`](#cấu-trúc-dữ-liệu-ina_dev_list)
- [Node 1: Xử lý message từ NetAlertX](#node-1-xử-lý-message-từ-netalertx)
- [Node 2: Kiểm tra ngưỡng 15 phút](#node-2-kiểm-tra-ngưỡng-15-phút)
- [Cấu hình có thể chỉnh](#cấu-hình-có-thể-chỉnh)
- [Các trường hợp biên đã xử lý](#các-trường-hợp-biên-đã-xử-lý)
- [Giới hạn / điều cần biết](#giới-hạn--điều-cần-biết)
- [Troubleshooting](#troubleshooting)

## Ý tưởng tổng quan

NetAlertX bắn ra sự kiện `Disconnected`/`Connected` cho từng thiết bị mỗi khi
trạng thái mạng của nó thay đổi. Với thiết bị quan trọng (tên chứa `"skylog"`,
không phân biệt hoa thường), nếu nó mất kết nối và **không quay lại trong vòng
15 phút**, hệ thống cần bắn thêm 1 cảnh báo riêng, nghiêm trọng hơn — vì đây là
dấu hiệu sự cố thật, không phải chập chờn mạng thoáng qua.

Cách làm: khi nhận sự kiện Disconnected, lưu lại **thời điểm mất kết nối** vào
context storage. Một Inject node chạy định kỳ (mỗi 5-10 giây) sẽ quét toàn bộ
danh sách, so sánh thời gian hiện tại với thời điểm lưu — nếu vượt 15 phút và
thiết bị chưa hồi phục, gửi cảnh báo. Khi thiết bị Connected trở lại, xoá mốc
thời gian này để không cảnh báo trùng và để sẵn sàng theo dõi lần mất kết nối
tiếp theo.

## Sơ đồ luồng

```
[NetAlertX message] ──► [Function: Xử lý message NetAlertX] ──► (không forward msg,
                                chỉ ghi/xoá pending trong Ina_dev_list)

[Inject, lặp mỗi N giây] ──► [Function: Kiểm tra ngưỡng 15 phút] ──► [msg cảnh báo]
                                     (đọc từ Ina_dev_list)              ──► gửi Telegram
```

Hai function này **không nối trực tiếp với nhau** — chúng giao tiếp gián tiếp
qua context storage `Ina_dev_list` (dùng chung 1 store tên `"file"`, persistent
qua các lần Node-RED khởi động lại).

## Cấu trúc dữ liệu: `Ina_dev_list`

Lưu bằng `flow.get`/`flow.set` (context store `"file"`), là 1 object keyed theo
**tên thiết bị** (`devName`), ví dụ:

```jsonc
{
    "Skylog-2": {
        "mac": "00:90:e9:00:50:e5",         // giả định được pre-populate sẵn, không tự động ghi
        "devVendor": "JANZ COMPUTER AG",    // giả định pre-populate sẵn
        "eveIp": "172.24.2.1",              // giả định pre-populate sẵn
        "pending": {                        // field CHỈ tồn tại khi thiết bị đang mất kết nối
            "ts": 1758686800000,            // Date.now() tại thời điểm Disconnected
            "alerted": false,               // true sau khi đã gửi cảnh báo 15 phút
            "lastUpdated": "2026-09-24T10:34:13.613Z"  // set khi alerted chuyển true
        }
    },
    "Skylog-3": { "mac": "...", ... }       // không có "pending" = đang online bình thường
}
```

Điểm quan trọng: **field `pending` chỉ xuất hiện khi thiết bị đang trong trạng
thái mất kết nối**. Nó bị xoá hoàn toàn (`delete config.pending`) ngay khi thiết
bị Connected trở lại — không giữ lại lịch sử.

`mac`, `devVendor`, `eveIp` **không được 2 function này tự động ghi** — theo
thiết kế, các field này được giả định đã pre-populate sẵn trong `Ina_dev_list`
từ trước (vì thiết bị dùng IP tĩnh, thông tin cố định), tránh rủi ro NetAlertX
gửi data không đáng tin đè lên thông tin đã xác thực.

## Node 1: Xử lý message từ NetAlertX

**Vai trò**: nhận từng sự kiện JSON từ NetAlertX, cập nhật `pending` trong
`Ina_dev_list`. Không forward message đi đâu — node này là "ghi log trạng
thái", không phải "gửi cảnh báo".

```js
const KEYWORD = "skylog";
const STORE   = "file";
const KEY     = "Ina_dev_list";

const evt = msg.payload;
if (!evt || !evt.devName) return null;

// Chỉ xử lý thiết bị có tên chứa "skylog" (không phân biệt hoa thường)
if (!evt.devName.toLowerCase().includes(KEYWORD)) return null;

const type = evt.eveEventType;
if (type !== "Disconnected" && type !== "Connected") return null; // bỏ qua IP Changed, v.v.

const devName = evt.devName;
let devDB = flow.get(KEY, STORE);
let config = devDB[devName];
if (!config) {
    config = {};
    devDB[devName] = config;
}

if (type === "Disconnected" && !config.pending) {
    // Chỉ tạo mốc mới nếu CHƯA có pending — tránh reset timer khi
    // NetAlertX gửi trùng lặp nhiều tin Disconnected liên tiếp
    config.pending = { ts: Date.now(), alerted: false };
    flow.set(KEY, devDB, STORE);
    node.status({ fill: "red", shape: "ring", text: `${evt.devName} down – timer started` });
}

if (type === "Connected") {
    delete config["pending"];
    flow.set(KEY, devDB, STORE);
    node.status({ fill: "green", shape: "dot", text: `${evt.devName} back online` });
}
```

**Từng bước xử lý**:

1. Bỏ qua nếu không phải sự kiện của thiết bị nhóm "skylog", hoặc không phải
   `Disconnected`/`Connected`.
2. Lấy (hoặc tạo mới nếu chưa từng có) record của thiết bị trong `devDB`.
3. Nếu `Disconnected` **và chưa có `pending`**: tạo mốc `{ts, alerted: false}`.
   Nếu đã có `pending` rồi (thiết bị đang down), **không làm gì** — giữ nguyên
   mốc thời gian ban đầu.
4. Nếu `Connected`: xoá `pending` hoàn toàn, bất kể đã `alerted` hay chưa —
   coi như "reset" để chuẩn bị theo dõi lần down kế tiếp.

## Node 2: Kiểm tra ngưỡng 15 phút

**Vai trò**: chạy định kỳ (Inject node, khuyến nghị 5-10 giây/lần), quét toàn
bộ `Ina_dev_list`, tìm thiết bị đang `pending` quá 15 phút mà chưa `alerted`,
sinh message cảnh báo.

```js
const THRESHOLD_MS = 15 * 60 * 1000;
const searchStr = "skylog".toLowerCase();
const context_name = "Ina_dev_list";
const STORE = "file";
let changed = false;
const out = [];

let now = msg.payload;   // ⚠️ Inject node phải set Payload = "timestamp" (số ms)
let full_obj = flow.get(context_name, STORE);
const keys = Object.keys(full_obj);
const matchingKeys = keys.filter(key => key.toLowerCase().includes(searchStr));

matchingKeys.forEach(key => {
    const dev_obj = full_obj[key];
    const pending = dev_obj["pending"] || {};

    if (!pending.ts || pending.alerted) return; // bỏ qua: đang online, hoặc đã cảnh báo rồi

    if (now - pending.ts >= THRESHOLD_MS) {
        pending.alerted = true;
        pending.lastUpdated = new Date().toISOString();
        changed = true;

        out.push({
            topic: "skylog-offline-15m",
            devName: key,
            payload: `🚨 Skylog OFFLINE > 15 min
━━━━━━━━━━━━━━━━━━━━━
Device: ${dev_obj.devName || dev_obj.mac || key}
MAC: ${dev_obj.mac}
Vendor: ${dev_obj.devVendor || "-"}
IP: ${dev_obj.eveIp || "-"}
Disconnected at: ${new Date(pending.ts).toLocaleString()}
Still not back online after 15 minutes!
━━━━━━━━━━━━━━━━━━━━━`
        });
    }
});

if (changed) flow.set(context_name, full_obj, STORE);

const pendingCount = Object.values(full_obj).filter(r => r.pending?.ts && !r.pending?.alerted).length;
node.status(pendingCount
    ? { fill: "yellow", shape: "ring", text: `${pendingCount} Skylog pending` }
    : { fill: "green", shape: "dot", text: "all OK" });

return out.length ? [out] : null;
```

**Từng bước xử lý**:

1. Lọc ra các key (tên thiết bị) trong `devDB` chứa `"skylog"` — quét toàn bộ,
   không giới hạn 1 thiết bị.
2. Với mỗi thiết bị: nếu không có `pending.ts` (đang online) hoặc đã
   `alerted: true` (đã cảnh báo rồi, chưa reconnect) → bỏ qua, không xử lý
   tiếp (dùng `return` bên trong `forEach` — tương đương `continue`).
3. Nếu `now - pending.ts >= 15 phút` → set `alerted = true`, build message
   cảnh báo, đẩy vào mảng `out`.
4. Chỉ `flow.set()` lưu lại **nếu có gì thay đổi** (`changed = true`) — tránh
   ghi context liên tục mỗi lần Inject chạy dù không có gì mới.
5. Cập nhật `node.status` hiển thị số lượng thiết bị đang chờ (pending, chưa
   alerted) ngay trên node, tiện nhìn nhanh trạng thái tổng quan.
6. Trả về mảng message qua 1 output duy nhất — 1 lần chạy có thể sinh **nhiều**
   message nếu nhiều thiết bị cùng vượt ngưỡng cùng lúc.

## Cấu hình có thể chỉnh

| Biến | Ý nghĩa | Vị trí |
|---|---|---|
| `KEYWORD` / `searchStr` | Từ khoá lọc tên thiết bị (hiện: `"skylog"`) | Cả 2 function — **phải giống nhau** |
| `THRESHOLD_MS` | Ngưỡng thời gian coi là "down quá lâu" (hiện: 15 phút) | Node 2 |
| `STORE` | Tên context store (hiện: `"file"` — persistent qua restart) | Cả 2 function |
| `KEY` / `context_name` | Tên biến lưu database (hiện: `"Ina_dev_list"`) | Cả 2 function — **phải giống nhau** |
| Chu kỳ Inject node | Tần suất quét ngưỡng 15 phút | Config của Inject node, khuyến nghị 5-10s |

## Các trường hợp biên đã xử lý

- **NetAlertX gửi trùng nhiều tin Disconnected liên tiếp** (mạng chập chờn khi
  vừa rớt): nhờ check `!config.pending`, mốc thời gian giữ nguyên từ lần đầu,
  không bị reset liên tục.
- **Thiết bị reconnect trước khi đủ 15 phút**: `pending` bị xoá ngay khi có
  event `Connected`, không bao giờ có cảnh báo "offline 15 phút" bị gửi trễ
  cho 1 lần down đã kết thúc.
- **Thiết bị down lần 2 sau khi đã từng alerted và reconnect**: vì `pending`
  bị xoá hoàn toàn lúc Connected, lần down tiếp theo tạo `pending` mới với
  `alerted: false` — cảnh báo hoạt động lại bình thường cho chu kỳ mới.
- **Nhiều thiết bị "skylog" down cùng lúc**: Node 2 dùng `forEach` quét hết
  toàn bộ danh sách mỗi lần chạy, không giới hạn xử lý 1 thiết bị/lượt.
- **Node-RED restart giữa chừng lúc thiết bị đang down**: vì dùng context
  store `"file"` (ghi ra đĩa), mốc `pending.ts` không bị mất, bộ đếm 15 phút
  tiếp tục đúng sau khi Node-RED khởi động lại.

## Giới hạn / điều cần biết

- **Không dùng `Time:` string từ NetAlertX để tính mốc** — dùng `Date.now()`
  của chính Node-RED tại thời điểm nhận event, tránh phụ thuộc format/locale
  không ổn định.
- **Store `"file"` mặc định ghi xuống đĩa mỗi 30 giây** (`flushInterval`), không
  phải ngay lập tức — nếu Node-RED crash đúng lúc vừa nhận Disconnected (trong
  vòng 30s chưa kịp flush), mốc thời gian đó có thể mất. Muốn chặt hơn, thêm
  `config: { flushInterval: 5 }` vào cấu hình context store `"file"` trong
  `settings.js`.
- **`mac`/`devVendor`/`eveIp` không tự cập nhật** — nếu thiết bị đổi vendor/IP
  thật (hiếm khi xảy ra với thiết bị IP tĩnh), phải sửa tay trong
  `Ina_dev_list`, 2 function này sẽ không tự đồng bộ lại từ NetAlertX.
- **`flow` context yêu cầu 2 function nằm cùng 1 flow tab** trong Node-RED —
  nếu tách sang tab khác, phải đổi `flow.get`/`flow.set` thành `global.get`/
  `global.set` ở cả 2 nơi.

## Troubleshooting

| Triệu chứng | Khả năng nguyên nhân |
|---|---|
| Không bao giờ có cảnh báo 15 phút, dù thiết bị down thật lâu | Tên field lệch nhau giữa 2 function (ví dụ 1 bên ghi `ts`, bên kia đọc `timestamp`) — kiểm tra bằng debug node đọc `Ina_dev_list` trực tiếp qua `flow.get` trong 1 Inject test riêng |
| `node.status` luôn "all OK" dù chắc chắn có thiết bị down | `now = msg.payload` không phải số (Inject node chưa set Payload = timestamp) |
| Sau khi restart Node-RED, dữ liệu `pending` bị mất | Context store đang dùng `"default"` (memory) thay vì `"file"`, hoặc `settings.js` chưa khai báo store `"file"` đúng cách |
| Cảnh báo gửi liên tục lặp lại nhiều lần cho cùng 1 lần down | Thiếu bước set `pending.alerted = true` sau khi cảnh báo, hoặc dòng check `pending.alerted` ở đầu function 2 bị xoá nhầm |
| 1 thiết bị "biến mất" khỏi `Ina_dev_list` sau khi thiết bị khác Connected | Bug `flow.set()`/`global.set()` bị gọi với data sai (ghi đè 1 phần nhỏ lên toàn bộ database) — kiểm tra lại đúng biến `devDB` được truyền vào, không phải 1 object con |
