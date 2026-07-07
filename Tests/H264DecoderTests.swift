//
//  H264DecoderTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

#if !os(watchOS)

import CoreMedia
import Foundation
import Testing
import H264Decoder

/// 收集 `H264Decoder` 回呼結果的測試替身。
private final class FrameCollector: H264DecoderDelegate {

    /// 依回呼順序收到的樣本緩衝。
    private(set) var sampleBuffers: [CMSampleBuffer] = []

    /// 記下解碼器送出的每一個 `CMSampleBuffer`，模擬會長期持有輸出的下游。
    func newFrame(_ decoder: H264Decoder, decoded frame: CMSampleBuffer) {
        sampleBuffers.append(frame)
    }
}

private final class H264DecoderTests {

    /// 組出單一 NAL 的 Annex-B 位元流：4 位元組 start code 接 NAL 內容。
    private func annexBStream(of nals: [[UInt8]]) -> Data {
        var stream = Data()
        for nal in nals {
            stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            stream.append(contentsOf: nal)
        }
        return stream
    }

    /// 產生指定填充值的非 IDR 切片 NAL（type 1）；內容無連續零、不會被誤判成 start code。
    private func sliceNAL(filledWith byte: UInt8, payloadCount: Int) -> [UInt8] {
        var nal: [UInt8] = [0x61]
        nal.append(contentsOf: [UInt8](repeating: byte, count: payloadCount))
        return nal
    }

    /// 解碼器輸出的 `CMSampleBuffer` 底層資料必須是自持的複本：
    /// 來源封包記憶體釋放並被之後的配置重複使用後，先前輸出的內容不得跟著改變。
    @Test
    func `delivered sample buffer keeps bytes after source packet memory is reused`() throws {
        let decoder = H264Decoder(to: .CMSampleBuffer)
        let collector = FrameCollector()
        decoder.delegate = collector
        let firstNAL = sliceNAL(filledWith: 0x11, payloadCount: 4_096)
        decoder.qnqueue(annexBStream(of: [firstNAL]))
        #expect(collector.sampleBuffers.count == 1)
        let sampleBuffer = try #require(collector.sampleBuffers.first)
        let dataBuffer = try #require(CMSampleBufferGetDataBuffer(sampleBuffer))
        // 再解一個同尺寸封包、並大量配置同尺寸陣列，促使第一個封包釋放後的記憶體被重複使用。
        decoder.qnqueue(annexBStream(of: [sliceNAL(filledWith: 0x22, payloadCount: 4_096)]))
        let churn: [[UInt8]] = (0 ..< 64).map { _ in [UInt8](repeating: 0xAA, count: firstNAL.count + 4) }
        var readBack = [UInt8](repeating: 0, count: firstNAL.count + 4)
        let status: OSStatus = CMBlockBufferCopyDataBytes(
            dataBuffer, atOffset: 0, dataLength: readBack.count, destination: &readBack)
        #expect(status == kCMBlockBufferNoErr)
        var expected: [UInt8] = withUnsafeBytes(of: UInt32(firstNAL.count).bigEndian, Array.init)
        expected.append(contentsOf: firstNAL)
        #expect(readBack == expected, "輸出緩衝的內容不得因來源封包記憶體被重用而變動")
        withExtendedLifetime(churn) {}
    }

    /// 尚未收到 SPS / PPS 前的 IDR 封包應被安全丟棄、不觸發回呼也不 crash。
    @Test
    func `idr packet before parameter sets is dropped without crash`() {
        let decoder = H264Decoder(to: .CMSampleBuffer)
        let collector = FrameCollector()
        decoder.delegate = collector
        var idr: [UInt8] = [0x65]
        idr.append(contentsOf: [UInt8](repeating: 0x33, count: 32))
        decoder.qnqueue(annexBStream(of: [idr]))
        #expect(collector.sampleBuffers.isEmpty)
    }

    /// SPS + PPS 後的 IDR 應建立 format description 並隨樣本緩衝輸出。
    @Test
    func `idr packet after parameter sets carries format description`() throws {
        let decoder = H264Decoder(to: .CMSampleBuffer)
        let collector = FrameCollector()
        decoder.delegate = collector
        let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0A, 0xF8, 0x41, 0xA2]
        let pps: [UInt8] = [0x68, 0xCE, 0x38, 0x80]
        var idr: [UInt8] = [0x65]
        idr.append(contentsOf: [UInt8](repeating: 0x33, count: 32))
        decoder.qnqueue(annexBStream(of: [sps, pps, idr]))
        #expect(collector.sampleBuffers.count == 1)
        let sampleBuffer = try #require(collector.sampleBuffers.first)
        #expect(CMSampleBufferGetFormatDescription(sampleBuffer) != nil)
    }
}

#endif
