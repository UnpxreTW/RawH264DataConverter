//
//  H264Decoder
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

#if !os(watchOS)
import AVFoundation

public protocol H264DecoderDelegate: AnyObject {
    
    func newFrame(_ decoder: H264Decoder, decoded frame: CMSampleBuffer)
    
    func newFrame(_ decoder: H264Decoder, decoded frame: CVPixelBuffer)
}
public extension H264DecoderDelegate {
    
    func newFrame(_ decoder: H264Decoder, decoded frame: CMSampleBuffer) {}
    
    func newFrame(_ decoder: H264Decoder, decoded frame: CVPixelBuffer) {}
}
#endif
