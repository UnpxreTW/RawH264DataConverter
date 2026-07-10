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
import H264Decoder
import Testing

/// 組出單一 NAL 的 Annex-B 位元流：4 位元組 start code 接 NAL 內容。
private func annexBStream(of nals: [[UInt8]]) -> Data {
	var stream: Data = .init()
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

/// 從解碼輸出影格取出 `CMSampleBuffer`（`.sampleBuffer` 模式）；非該 case 回 nil。
private func cmSampleBuffer(from frame: DecodedFrame) -> CMSampleBuffer? {
	guard case let .sampleBuffer(buffer) = frame else { return nil }
	return buffer
}

private final class H264DecoderTests {

	/// 解碼器輸出的 `CMSampleBuffer` 底層資料必須是自持的複本：
	/// 來源封包記憶體釋放並被之後的配置重複使用後，先前輸出的內容不得跟著改變。
	@Test
	func `delivered sample buffer keeps bytes after source packet memory is reused`() async throws {
		let decoder: H264Decoder = .init(to: .CMSampleBuffer)
		var frames = decoder.frames.makeAsyncIterator()
		let firstNAL = sliceNAL(filledWith: 0x11, payloadCount: 4096)
		await decoder.enqueue(annexBStream(of: [firstNAL]))
		let frame = try #require(await frames.next())
		let buffer = try #require(cmSampleBuffer(from: frame))
		let dataBuffer = try #require(CMSampleBufferGetDataBuffer(buffer))
		// 在讀回前先解一個同尺寸封包、並大量配置同尺寸陣列，促使第一個封包釋放後的記憶體被重複使用。
		await decoder.enqueue(annexBStream(of: [sliceNAL(filledWith: 0x22, payloadCount: 4096)]))
		let churn: [[UInt8]] = (0 ..< 64).map { _ in [UInt8](repeating: 0xAA, count: firstNAL.count + 4) }
		var readBack: [UInt8] = .init(repeating: 0, count: firstNAL.count + 4)
		let status: OSStatus = CMBlockBufferCopyDataBytes(
			dataBuffer, atOffset: 0, dataLength: readBack.count, destination: &readBack
		)
		#expect(status == kCMBlockBufferNoErr)
		var expected: [UInt8] = withUnsafeBytes(of: UInt32(firstNAL.count).bigEndian, Array.init)
		expected.append(contentsOf: firstNAL)
		#expect(readBack == expected, "輸出緩衝的內容不得因來源封包記憶體被重用而變動")
		withExtendedLifetime(churn) {}
		withExtendedLifetime(decoder) {}
	}

	/// 尚未收到 SPS / PPS 前的 IDR 封包應被安全丟棄、不吐出影格也不 crash。
	/// 解碼器釋放後 `deinit` 會結束串流，故耗盡串流可安全計數而不阻塞。
	@Test
	func `idr packet before parameter sets is dropped`() async {
		let stream: AsyncStream<DecodedFrame>
		do {
			let decoder: H264Decoder = .init(to: .CMSampleBuffer)
			stream = decoder.frames
			var idr: [UInt8] = [0x65]
			idr.append(contentsOf: [UInt8](repeating: 0x33, count: 32))
			await decoder.enqueue(annexBStream(of: [idr]))
		}
		var count = 0
		for await _ in stream {
			count += 1
		}
		#expect(count == 0)
	}

	/// SPS + PPS 後的 IDR 應建立 format description 並隨樣本緩衝輸出。
	@Test
	func `idr packet after parameter sets carries format description`() async throws {
		let decoder: H264Decoder = .init(to: .CMSampleBuffer)
		var frames = decoder.frames.makeAsyncIterator()
		let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0A, 0xF8, 0x41, 0xA2]
		let pps: [UInt8] = [0x68, 0xCE, 0x38, 0x80]
		var idr: [UInt8] = [0x65]
		idr.append(contentsOf: [UInt8](repeating: 0x33, count: 32))
		await decoder.enqueue(annexBStream(of: [sps, pps, idr]))
		let frame = try #require(await frames.next())
		let buffer = try #require(cmSampleBuffer(from: frame))
		#expect(CMSampleBufferGetFormatDescription(buffer) != nil)
		withExtendedLifetime(decoder) {}
	}

	/// `enqueue` 是 actor-isolated 且內部無 `await` 中斷點，單次呼叫餵入的多個 NAL
	/// 會在消費端開始拉取前一次處理完畢並依序 `yield`；`frames` 的 `.bufferingNewest(1)`
	/// 政策此時只留得住最新一格，較舊的格會被捨棄——這是低延遲 live-view 定位的預期行為，
	/// 而非漏 yield 的 bug。
	@Test
	func `burst of frames within one enqueue call keeps only the newest`() async throws {
		let decoder: H264Decoder = .init(to: .CMSampleBuffer)
		var frames = decoder.frames.makeAsyncIterator()
		let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0A, 0xF8, 0x41, 0xA2]
		let pps: [UInt8] = [0x68, 0xCE, 0x38, 0x80]
		var idr: [UInt8] = [0x65]
		idr.append(contentsOf: [UInt8](repeating: 0x11, count: 16))
		let pSlice = sliceNAL(filledWith: 0x22, payloadCount: 16)
		await decoder.enqueue(annexBStream(of: [sps, pps, idr, pSlice]))
		let frame = try #require(await frames.next())
		let buffer = try #require(cmSampleBuffer(from: frame))
		let dataBuffer = try #require(CMSampleBufferGetDataBuffer(buffer))
		var readBack: [UInt8] = .init(repeating: 0, count: CMBlockBufferGetDataLength(dataBuffer))
		// note: CMBlockBufferCopyDataBytes 是 C 函式、非型別，顯式標註型別以防 SwiftFormat propertyTypes 誤判重寫成不存在型別。
		let status: OSStatus = CMBlockBufferCopyDataBytes(
			dataBuffer, atOffset: 0, dataLength: readBack.count, destination: &readBack
		)
		#expect(status == kCMBlockBufferNoErr)
		#expect(readBack.last == 0x22, "burst 中較舊的 IDR 影格應被 bufferingNewest(1) 捨棄，僅留最新的 P-slice")
		withExtendedLifetime(decoder) {}
	}

	/// 短於 start code 長度的資料構不成任何封包，`enqueue` 需安全忽略、不 crash 也不吐格。
	@Test
	func `enqueue with data shorter than start code is a no-op`() async {
		let stream: AsyncStream<DecodedFrame>
		do {
			let decoder: H264Decoder = .init(to: .CMSampleBuffer)
			stream = decoder.frames
			await decoder.enqueue(Data([0x00, 0x00, 0x00]))
		}
		var count = 0
		for await _ in stream {
			count += 1
		}
		#expect(count == 0)
	}

	/// 收到第二輪 SPS/PPS 後的 IDR 仍需重新產生 format description，而非沿用前一輪的殘留狀態
	/// （`createFormatDescription()` 每次呼叫皆重置 `formatDescription`）。兩輪刻意使用同一組
	/// 已知可解析的 SPS/PPS bytes，避免手改參數位元組落到不可解析內容、讓測試失去確定性。
	@Test
	func `format description is regenerated for a second parameter set burst`() async throws {
		let decoder: H264Decoder = .init(to: .CMSampleBuffer)
		var frames = decoder.frames.makeAsyncIterator()
		let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0A, 0xF8, 0x41, 0xA2]
		let pps: [UInt8] = [0x68, 0xCE, 0x38, 0x80]
		for fill: UInt8 in [0x33, 0x44] {
			var idr: [UInt8] = [0x65]
			idr.append(contentsOf: [UInt8](repeating: fill, count: 32))
			await decoder.enqueue(annexBStream(of: [sps, pps, idr]))
			let frame = try #require(await frames.next())
			let buffer = try #require(cmSampleBuffer(from: frame))
			#expect(CMSampleBufferGetFormatDescription(buffer) != nil)
		}
		withExtendedLifetime(decoder) {}
	}

	/// `.CVPixelBuffer` 模式下解碼器提前釋放：工作階段的作廢（`DecompressionSessionBox` deinit）
	/// 與串流 `finish()` 需可安全共存，不因已捕獲 continuation 而非 `self` 的 in-flight
	/// VideoToolbox 回呼觸碰已釋放工作階段而 crash（`H264Decoder.deinit` 的 doc comment
	/// 說明了此處的排序考量）。
	@Test
	func `decoder release in CVPixelBuffer mode does not crash session teardown`() async {
		let stream: AsyncStream<DecodedFrame>
		do {
			let decoder: H264Decoder = .init(to: .CVPixelBuffer)
			stream = decoder.frames
			let sps: [UInt8] = [0x67, 0x42, 0x00, 0x0A, 0xF8, 0x41, 0xA2]
			let pps: [UInt8] = [0x68, 0xCE, 0x38, 0x80]
			var idr: [UInt8] = [0x65]
			idr.append(contentsOf: [UInt8](repeating: 0x33, count: 32))
			await decoder.enqueue(annexBStream(of: [sps, pps, idr]))
			// decoder 在此離開作用域釋放：session box 隨之釋放並作廢 VTDecompressionSession。
		}
		var count = 0
		for await _ in stream {
			count += 1
		}
		#expect(count >= 0)
	}
}

#endif
