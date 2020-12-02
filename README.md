# H264Decoder

將 Raw H.264 Data 轉換為 CMSampleBuffer

## 使用方式

1. 建立 Decoder 實例：
```swift
var decoder = H264Decoder()
```
2. 設定解碼完成後 `CMSampleBuffer` 輸出流：
```swift
decoder.setHandler { <#T##Output Buffer##CMSampleBuffer#> in
    // doSomething
}
```
3. 將 Raw H.264 Data 傳入 Decoder 實例進行解碼：
```swift
decoder.qnqueue(<#T##Raw H.264 Data##Data#>)
```
