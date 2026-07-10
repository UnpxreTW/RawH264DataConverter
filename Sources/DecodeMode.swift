//
//  H264Decoder
//
//  Copyright © 2020 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

/// `H264Decoder` 的解碼輸出型別選項。
public enum DecodeMode {

	/// 輸出 `CMSampleBuffer`：可直接餵 `AVSampleBufferDisplayLayer` 顯示，不經二次轉換。
	case CMSampleBuffer

	/// 輸出 `CVPixelBuffer`：經 `VTDecompressionSession` 解出像素緩衝，供需要直接存取像素資料的場景使用。
	case CVPixelBuffer
}
