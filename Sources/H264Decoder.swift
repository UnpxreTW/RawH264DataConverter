//
//  H264Decoder
//
//  Copyright © 2020 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

#if !os(watchOS)
import AVFoundation
import VideoToolbox

private typealias Byte = UInt8
private typealias VideoPacket = [Byte]

/// 以 RAII 包住 `VTDecompressionSession`，於自身釋放時作廢工作階段。
///
/// `actor` 的 `nonisolated deinit` 不能存取非 `Sendable` 的 isolated 屬性
/// （`isolated deinit` 可以、但需 macOS 15.4，超出本套件部署下限），故把工作階段的生命週期
/// 綁在這個 class 上：解碼器釋放時連帶釋放本盒，於本盒 `deinit`（非 actor-isolated、可存取
/// 自身屬性）作廢工作階段，確保 in-flight 的非同步 VideoToolbox 回呼不會觸碰已釋放的 session。
private final class DecompressionSessionBox {
	init(_ session: VTDecompressionSession) {
		self.session = session
	}

	deinit { VTDecompressionSessionInvalidate(session) }

	let session: VTDecompressionSession
}

/// 裸 H.264 Annex-B 位元流解碼器。
///
/// 把切好或未切的 Annex-B byte blob 餵進 ``enqueue(_:)``，解出的影格從 ``frames``
/// 非同步串流吐出；輸出型別（`CMSampleBuffer` 或 `CVPixelBuffer`）由初始化時的
/// ``DecodeMode`` 固定。型別為 `actor`，`VideoToolbox` 的跨執行緒解碼回呼只觸碰
/// `Sendable` 的串流 continuation，無資料競爭。
public actor H264Decoder {

	// MARK: Public

	/// 解碼輸出串流。型別由初始化時的 ``DecodeMode`` 決定，用 `for await` 消費。
	///
	/// 緩衝政策為 `.bufferingNewest(1)`：消費端跟不上時只保留最新一格、丟棄舊格，
	/// 貼合即時顯示（live-view）低延遲定位、避免影格無上限堆積導致記憶體膨脹。
	public nonisolated let frames: AsyncStream<DecodedFrame>

	/// 餵入一段 Annex-B 位元流（可跨多個 NAL access unit），逐包解碼後吐進 ``frames``。
	public func enqueue(_ data: Data) {
		var data = data
		while var packet = findPacket(from: &data) {
			receivedRawVideoFrame(in: &packet)
		}
	}

	public init(to mode: DecodeMode = .CMSampleBuffer) {
		self.decodeMode = mode
		var capturedContinuation: AsyncStream<DecodedFrame>.Continuation!
		self.frames = AsyncStream<DecodedFrame>(bufferingPolicy: .bufferingNewest(1)) { capturedContinuation = $0 }
		self.continuation = capturedContinuation
	}

	// MARK: Lifecycle

	deinit {
		// 結束串流。解碼工作階段的作廢綁在 ``DecompressionSessionBox`` 的 deinit：本 actor
		// 釋放時連帶釋放該盒即作廢，確保 in-flight 的非同步 VideoToolbox 回呼（捕獲
		// continuation 而非 self、已無 `[weak self]` 護欄）不會觸碰已釋放的工作階段；串流結束後
		// 才發生的 yield 為安全 no-op，故先後順序不影響安全性。
		continuation.finish()
	}

	// MARK: Private

	private let startCode: Data = .init([0x00, 0x00, 0x00, 0x01])
	private let decodeMode: DecodeMode
	private let continuation: AsyncStream<DecodedFrame>.Continuation
	private var formatDescription: CMVideoFormatDescription?
	private var sessionBox: DecompressionSessionBox?
	private var sps: VideoPacket?
	private var pps: VideoPacket?

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
		// note: CFSwapInt32HostToBig 是 C 函式、非型別，顯式標註型別以防 SwiftFormat propertyTypes 誤判重寫成不存在型別。
		var length: UInt32 = CFSwapInt32HostToBig(UInt32(videoPacket.count - start))
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
		guard let sps, let pps, !sps.isEmpty, !pps.isEmpty else { return false }
		let status = makeVideoFormatDescription(sps: sps, pps: pps)
		if case .CVPixelBuffer = decodeMode, let description = formatDescription {
			return createDecompressionSession(for: description)
		} else {
			return status == noErr
		}
	}

	/// 用 SPS/PPS 位元組建立 ``formatDescription``，回傳底層 C API 的建立狀態碼。
	private func makeVideoFormatDescription(sps: VideoPacket, pps: VideoPacket) -> OSStatus {
		let parameterSizes = [sps.count, pps.count]
		return sps.withUnsafeBufferPointer { spsPointer -> OSStatus in
			pps.withUnsafeBufferPointer { ppsPointer -> OSStatus in
				guard let spsAddress = spsPointer.baseAddress, let ppsAddress = ppsPointer.baseAddress else {
					return kCMFormatDescriptionError_InvalidParameter
				}
				let parameterSet = [spsAddress, ppsAddress]
				return parameterSet.withUnsafeBufferPointer { parameterSetPointer -> OSStatus in
					parameterSizes.withUnsafeBufferPointer { parameterSizesPointer -> OSStatus in
						guard
							let parameterSetAddress = parameterSetPointer.baseAddress,
							let parameterSizesAddress = parameterSizesPointer.baseAddress
						else {
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
	}

	/// `.CVPixelBuffer` 模式下依 format description 建立 `VTDecompressionSession` 並持有進 ``sessionBox``。
	/// note: VTDecompressionSessionCreate 是 C 函式、非型別，顯式標註型別以防 SwiftFormat propertyTypes 誤判重寫成不存在型別。
	private func createDecompressionSession(for description: CMVideoFormatDescription) -> Bool {
		sessionBox = nil
		// swiftlint:disable:next identifier_name
		var _decompressionSession: VTDecompressionSession?
		let decoderParameters: NSMutableDictionary = .init()
		let destinationPixelBufferAttributes: NSMutableDictionary = .init()
		destinationPixelBufferAttributes.setValue(
			NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32),
			forKey: kCVPixelBufferPixelFormatTypeKey as String
		)
		let status: OSStatus = VTDecompressionSessionCreate(
			allocator: kCFAllocatorDefault,
			formatDescription: description,
			decoderSpecification: decoderParameters,
			imageBufferAttributes: destinationPixelBufferAttributes,
			outputCallback: nil,
			decompressionSessionOut: &_decompressionSession
		)
		guard status == noErr else { return false }
		sessionBox = _decompressionSession.map(DecompressionSessionBox.init)
		return true
	}

	private func decode(_ packet: VideoPacket) {
		guard let blockBuffer = makeBlockBuffer(from: packet) else { return }
		guard let buffer = makeSampleBuffer(from: blockBuffer, sampleSize: packet.count) else { return }
		markDisplayImmediately(on: buffer)
		deliver(buffer)
	}

	/// 把封包位元組複製進新建的 `CMBlockBuffer`（自持複本，不共用來源記憶體）。
	/// note: CMBlockBufferCreateWithMemoryBlock 是 C 函式、非型別，顯式標註型別以防 SwiftFormat propertyTypes 誤判重寫成不存在型別。
	private func makeBlockBuffer(from packet: VideoPacket) -> CMBlockBuffer? {
		var blockBuffer: CMBlockBuffer?
		let createStatus: OSStatus = CMBlockBufferCreateWithMemoryBlock(
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
		guard createStatus == kCMBlockBufferNoErr, let ownedBlockBuffer = blockBuffer else { return nil }
		let copyStatus = packet.withUnsafeBytes { pointer -> OSStatus in
			guard let baseAddress = pointer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
			return CMBlockBufferReplaceDataBytes(
				with: baseAddress,
				blockBuffer: ownedBlockBuffer,
				offsetIntoDestination: 0,
				dataLength: packet.count
			)
		}
		guard copyStatus == kCMBlockBufferNoErr else { return nil }
		return ownedBlockBuffer
	}

	/// 把 `CMBlockBuffer` 包成單一影格的 `CMSampleBuffer`，套用當前 ``formatDescription``。
	/// note: CMSampleBufferCreateReady 是 C 函式、非型別，顯式標註型別以防 SwiftFormat propertyTypes 誤判重寫成不存在型別。
	private func makeSampleBuffer(from blockBuffer: CMBlockBuffer, sampleSize: Int) -> CMSampleBuffer? {
		var sampleBuffer: CMSampleBuffer?
		let sampleSizeArray = [sampleSize]
		let status: OSStatus = CMSampleBufferCreateReady(
			allocator: kCFAllocatorDefault,
			dataBuffer: blockBuffer,
			formatDescription: formatDescription,
			sampleCount: 1,
			sampleTimingEntryCount: 0,
			sampleTimingArray: nil,
			sampleSizeEntryCount: 1,
			sampleSizeArray: sampleSizeArray,
			sampleBufferOut: &sampleBuffer
		)
		guard status == kCMBlockBufferNoErr, let buffer = sampleBuffer else { return nil }
		return buffer
	}

	/// 標記樣本緩衝立即顯示（`kCMSampleAttachmentKey_DisplayImmediately`），略過內部緩衝排程延遲。
	/// note: CMSampleBufferGetSampleAttachmentsArray 是 C 函式、非型別，顯式標註型別以防 SwiftFormat propertyTypes 誤判重寫成不存在型別。
	private func markDisplayImmediately(on buffer: CMSampleBuffer) {
		let attachments: CFArray? = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true)
		// swiftlint:disable:next identifier_name
		guard let _attachments = attachments else { return }
		CFDictionarySetValue(
			unsafeBitCast(CFArrayGetValueAtIndex(_attachments, 0), to: CFMutableDictionary.self),
			Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
			Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
		)
	}

	/// 依 ``decodeMode`` 把樣本緩衝直接吐出，或送進 `VTDecompressionSession` 解出像素緩衝後吐出。
	private func deliver(_ buffer: CMSampleBuffer) {
		if case .CMSampleBuffer = decodeMode {
			continuation.yield(.sampleBuffer(buffer))
		} else {
			guard let session = sessionBox?.session else { return }
			let continuation = continuation
			var flag: [VTDecodeInfoFlags] = [.asynchronous, .frameDropped, .imageBufferModifiable]
			_ = VTDecompressionSessionDecodeFrame(
				session,
				sampleBuffer: buffer,
				flags: [._EnableTemporalProcessing],
				infoFlagsOut: &flag
			) { decodeStatus, _, imageBuffer, _, _ in
				if decodeStatus == noErr, let imageBuffer {
					continuation.yield(.pixelBuffer(imageBuffer))
				}
			}
		}
	}
}
#endif
