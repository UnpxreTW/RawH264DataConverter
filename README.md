# H264Decoder

將 Raw H.264 Data 轉換為 CMSampleBuffer 或 CVPixelBuffer

## 使用方式

1. 建立 Decoder 實例

預設初始化解碼為 CMSampleBuffer：
```swift
var decoder = H264Decoder()
```
或是指定初始化格式：
```swift
var decoder = H264Decoder(to: .CVPixelBuffer)
```

2. 設定解碼完成後輸出流

使自己的類別繼承 `H264DecoderDelegate` 並設定 Decoder 的 `delegate` 並實作方法以得到解碼完後的輸出

- note: 只有與解碼器設定同一個模式的輸出才會被觸發。
```swift
decoder.delegate = self

func newFrame(_ decoder: H264Decoder, decoded frame: CMSampleBuffer)

func newFrame(_ decoder: H264Decoder, decoded frame: CVPixelBuffer)
```

```swift
```

3. 將 Raw H.264 Data 傳入 Decoder 實例進行解碼
```swift
decoder.qnqueue(<#T##Raw H.264 Data##Data#>)
```
