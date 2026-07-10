# RawH264DataConverter

將 raw H.264 Annex-B 位元流轉換為 `CMSampleBuffer` 或 `CVPixelBuffer`，透過 VideoToolbox 解碼。

## 需求

- iOS 14+ / macOS 11+ / tvOS 14+
- Swift 6

## 安裝

以 Swift Package Manager 加入相依（目前尚未發佈對應版本標籤，先釘 branch）：

```swift
.package(url: "https://github.com/UnpxreTW/RawH264DataConverter.git", branch: "main")
```

並將 `H264Decoder` 加入 target 依賴。

## 使用

`H264Decoder` 是 `actor`：把 raw H.264 Annex-B 位元流餵進 `enqueue(_:)`，解碼結果從
`frames`（`AsyncStream<DecodedFrame>`）以 `for await` 拉取消費。

```swift
import H264Decoder
import AVFoundation

let decoder = H264Decoder(to: .CMSampleBuffer)
let displayLayer = AVSampleBufferDisplayLayer()

Task {
    for await frame in decoder.frames {
        guard case .sampleBuffer(let sampleBuffer) = frame else { continue }
        displayLayer.enqueue(sampleBuffer)
    }
}

// 收到網路 / 檔案來源的 raw H.264 Annex-B 資料時：
await decoder.enqueue(rawH264Data)
```

輸出型別由初始化時的 `DecodeMode` 決定：

- `.CMSampleBuffer`：輸出 `CMSampleBuffer`，可直接餵給 `AVSampleBufferDisplayLayer` 顯示。
- `.CVPixelBuffer`：經 `VTDecompressionSession` 解碼，輸出 `CVPixelBuffer`。

`frames` 採 `.bufferingNewest(1)` 緩衝政策：消費端跟不上時只保留最新一格、捨棄較舊的格，
貼合即時顯示（live-view）場景的低延遲定位；`enqueue(_:)` 於單次呼叫內解出多格時亦適用同一政策。

## 從 v1 遷移

v2 以 `actor` + `AsyncStream` 取代 v1 的 `delegate` 回呼介面：

- `H264Decoder` 由 `class` 改為 `actor`；建構後不再可用 `change(to:)` 於執行期切換輸出型別，
  改於初始化時以 `DecodeMode` 一次指定。
- 移除 `delegate` 屬性與 `H264DecoderDelegate`，改用 `frames`（`AsyncStream<DecodedFrame>`）
  以 `for await` 拉取解碼結果。
- `qnqueue(_:)` 更名為 `enqueue(_:)`，並改為 actor-isolated（呼叫需加 `await`）。

## 開發

建議使用 [Tuist](https://tuist.dev) 產生的專案檔進行開發

> Note: 使用產生 Xcode 專案開發以包含 `SwiftLint` 與 `SwiftFormat` 等工具

使用指令產生專案檔以進行開發：

```shell
tuist generate
```


> Note: 產生 Tuist 配置檔
>
> ```shell
> tuist edit
> ```

不需要 Tuist 時，最小驗證可直接走 SwiftPM（CI 即走此路徑）：

```shell
swift build
swift test
```
