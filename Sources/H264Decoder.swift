//
//  H264Decoder
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

#if !os(watchOS)
import VideoToolbox
import AVFoundation

private typealias Byte = UInt8
private typealias VideoPacket = Array<Byte>

public class H264Decoder {

    // MARK: Public Variable
    
    public weak var delegate: H264DecoderDelegate?
    
    // MARK: Private Variable

    private let startCode: Data = .init([0x00, 0x00, 0x00, 0x01])
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private var sps: VideoPacket?
    private var pps: VideoPacket?
    private var decodeMode: DecodeMode
    private var tempChangeMode: DecodeMode?
    
    // MARK: Lifecycle
    
    public init(to mode: DecodeMode = .CMSampleBuffer) {
        decodeMode = mode
    }

    // MARK: Public Function
    
    public func qnqueue(_ data: Data) {
        var data = data
        while var packet = findPacket(from: &data) {
            receivedRawVideoFrame(in: &packet)
        }
    }
    
    public func change(to mode: DecodeMode) {
        tempChangeMode = mode
    }

    // MARK: Private Function
    
    private func decodeDone() {
        guard let newMode = tempChangeMode else { return }
        decodeMode = newMode
        tempChangeMode = nil
    }

    private func findPacket(from data: inout Data) -> VideoPacket? {
        var packet: VideoPacket?
        guard data.count > startCode.count else { return nil }
        if let rear = data.range(of: startCode, in: startCode.count ..< data.count)?.lowerBound {
            packet = Array(data.subdata(in: 0 ..< rear))
            data.removeSubrange(0 ..< rear)
        } else {
            packet = Array(data)
            data.removeAll()
        }
        return packet
    }

    /// note: 對於 VideoToolBox 來說前四個位元並不是 StartCode 而應該為資料長度，所以需要手動填入。
    private func receivedRawVideoFrame(in videoPacket: inout VideoPacket) {
        guard videoPacket.count > 4 else { return }
        let start = 4
        var length = CFSwapInt32HostToBig(UInt32(videoPacket.count - start))
        memcpy(&videoPacket, &length, start)
        let nalType = videoPacket[start] & 0x1F
        switch nalType {
        case 0x05:
            guard createFormatDescription() else { return }
            decode(videoPacket)
        case 0x07:
            sps = Array(videoPacket[start ..< videoPacket.count])
        case 0x08:
            pps = Array(videoPacket[start ..< videoPacket.count])
        default:
            decode(videoPacket)
        }
    }

    private func createFormatDescription() -> Bool {
        if formatDescription != nil { formatDescription = nil }
        guard let sps = sps, let pps = pps, !sps.isEmpty, !pps.isEmpty else { return false }
        let parameterSizes = [sps.count, pps.count]
        let status = sps.withUnsafeBufferPointer { spsPointer -> OSStatus in
            pps.withUnsafeBufferPointer { ppsPointer -> OSStatus in
                guard let spsAddress = spsPointer.baseAddress, let ppsAddress = ppsPointer.baseAddress else {
                    return kCMFormatDescriptionError_InvalidParameter
                }
                let parameterSet = [spsAddress, ppsAddress]
                return parameterSet.withUnsafeBufferPointer { parameterSetPointer -> OSStatus in
                    parameterSizes.withUnsafeBufferPointer { parameterSizesPointer -> OSStatus in
                        guard let parameterSetAddress = parameterSetPointer.baseAddress,
                              let parameterSizesAddress = parameterSizesPointer.baseAddress else {
                            return kCMFormatDescriptionError_InvalidParameter
                        }
                        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: parameterSetAddress,
                            parameterSetSizes: parameterSizesAddress,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &formatDescription
                        )
                    }
                }
            }
        }
        if case .CVPixelBuffer = decodeMode, let description = formatDescription {
            if let session = decompressionSession {
                VTDecompressionSessionInvalidate(session)
            }
            // swiftlint:disable:next identifier_name
            var _decompressionSession: VTDecompressionSession?
            let decoderParameters = NSMutableDictionary()
            let destinationPixelBufferAttributes = NSMutableDictionary()
            destinationPixelBufferAttributes.setValue(
                NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32),
                forKey: kCVPixelBufferPixelFormatTypeKey as String)
            let status = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: description,
                decoderSpecification: decoderParameters,
                imageBufferAttributes: destinationPixelBufferAttributes,
                outputCallback: nil,
                decompressionSessionOut: &_decompressionSession)
            guard status == noErr else { return false }
            self.decompressionSession = _decompressionSession
            return true
        } else {
            return status == noErr
        }
    }

    private func decode(_ packet: VideoPacket) {
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: packet.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: packet.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let ownedBlockBuffer = blockBuffer else { return }
        status = packet.withUnsafeBytes { pointer -> OSStatus in
            guard let baseAddress = pointer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: ownedBlockBuffer,
                offsetIntoDestination: 0,
                dataLength: packet.count
            )
        }
        guard status == kCMBlockBufferNoErr else { return }
        var sampleBuffer: CMSampleBuffer?
        let sampleSizeArray = [packet.count]
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: ownedBlockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: sampleSizeArray,
            sampleBufferOut: &sampleBuffer)
        guard status == kCMBlockBufferNoErr, let buffer = sampleBuffer else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true)
        // swiftlint:disable:next identifier_name
        guard let _attachments = attachments else { return }
        CFDictionarySetValue(
            unsafeBitCast(CFArrayGetValueAtIndex(_attachments, 0), to: CFMutableDictionary.self),
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        if case .CMSampleBuffer = decodeMode {
            delegate?.newFrame(self, decoded: buffer)
        } else {
            guard let session = decompressionSession else { return }
            var flag: [VTDecodeInfoFlags] = [.asynchronous, .frameDropped, .imageBufferModifiable]
            status = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: buffer,
                flags: [._EnableTemporalProcessing],
                infoFlagsOut: &flag
            ) { [weak self] decodeStatus, _, CVImageBuffer, _, _ in
                guard let self = self else { return }
                if decodeStatus == noErr, let buffer = CVImageBuffer {
                    self.delegate?.newFrame(self, decoded: buffer)
                }
            }
        }
        decodeDone()
    }
}
#endif
