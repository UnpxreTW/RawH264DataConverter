//
//  H264DecoderDelegate.swift
//  H264Decoder
//
//  Created by UnpxreTW on 2020/11/30.
//  Copyright © 2020 UnpxreTW. All rights reserved.
//

import AVFoundation

public protocol H264DecoderDelegate: AnyObject {
    
    func newFrame(_ decoder: H264Decoder, decoded frame: CMSampleBuffer)
    
    func newFrame(_ decoder: H264Decoder, decoded frame: CVPixelBuffer)
}
public extension H264DecoderDelegate {
    
    func newFrame(_ decoder: H264Decoder, decoded frame: CMSampleBuffer) {}
    
    func newFrame(_ decoder: H264Decoder, decoded frame: CVPixelBuffer) {}
}
