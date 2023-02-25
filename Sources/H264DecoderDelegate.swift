//
//  H264DecoderDelegate.swift
//  H264Decoder
//
//  Copyright © 2023 UnpxreTW. All rights reserved.
//

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
