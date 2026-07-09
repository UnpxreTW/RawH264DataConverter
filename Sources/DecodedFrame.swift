//
//  H264Decoder
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

#if !os(watchOS)
import CoreMedia
import CoreVideo

/// 解碼輸出的單一影格，型別由 `H264Decoder` 初始化時的 ``DecodeMode`` 決定。
///
/// `@unchecked Sendable`：`CMSampleBuffer` / `CVPixelBuffer` 截至目前 SDK 尚未標註
/// `Sendable`，但每個影格的緩衝皆為單一影格新建、交給串流（yield）後解碼端不再變動，
/// 屬單一所有權跨 isolation 移交，可安全送出。
public enum DecodedFrame: @unchecked Sendable {

    /// `.CMSampleBuffer` 模式輸出：可直接餵 `AVSampleBufferDisplayLayer` 顯示。
    case sampleBuffer(CMSampleBuffer)

    /// `.CVPixelBuffer` 模式輸出：經 `VTDecompressionSession` 解出的像素緩衝。
    case pixelBuffer(CVPixelBuffer)
}
#endif
