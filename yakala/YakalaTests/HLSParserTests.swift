import XCTest

final class HLSParserTests: XCTestCase {
    let base = URL(string: "https://cdn.example.com/show/master.m3u8")!

    func testMasterWithSeparateAudio() throws {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",LANGUAGE="en",DEFAULT=YES,URI="audio/en.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Türkçe",LANGUAGE="tr",DEFAULT=NO,URI="audio/tr.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="aud"
        360/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",AUDIO="aud"
        https://other.example.com/1080/index.m3u8
        """
        guard case .master(let m) = try HLSParser.parse(text, baseURL: base) else { return XCTFail("not master") }
        XCTAssertEqual(m.variants.count, 2)
        XCTAssertEqual(m.variants[0].height, 1080, "highest quality first")
        XCTAssertEqual(m.variants[0].url.absoluteString, "https://other.example.com/1080/index.m3u8")
        XCTAssertEqual(m.variants[1].url.absoluteString, "https://cdn.example.com/show/360/index.m3u8")
        XCTAssertEqual(m.variants[1].codecs, "avc1.4d401e,mp4a.40.2", "quoted comma kept")
        XCTAssertEqual(m.audio(for: m.variants[0])?.url?.absoluteString, "https://cdn.example.com/show/audio/en.m3u8")
    }

    func testMediaWithKeysRangesAndMap() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:40
        #EXT-X-MAP:URI="init.mp4",BYTERANGE="720@0"
        #EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x0000000000000000000000000000ABCD
        #EXTINF:6.0,
        #EXT-X-BYTERANGE:1000@720
        media.mp4
        #EXTINF:5.5,title
        #EXT-X-BYTERANGE:500
        media.mp4
        #EXT-X-KEY:METHOD=NONE
        #EXTINF:4,
        tail.m4s
        #EXT-X-ENDLIST
        """
        guard case .media(let m) = try HLSParser.parse(text, baseURL: base) else { return XCTFail("not media") }
        XCTAssertFalse(m.isLive)
        XCTAssertEqual(m.segments.map(\.sequence), [40, 41, 42])
        XCTAssertEqual(m.totalDuration, 15.5, accuracy: 0.001)
        XCTAssertEqual(m.initSection?.byteRange, HLSByteRange(length: 720, offset: 0))
        XCTAssertEqual(m.segments[0].byteRange, HLSByteRange(length: 1000, offset: 720))
        XCTAssertEqual(m.segments[1].byteRange, HLSByteRange(length: 500, offset: 1720), "offset continues")
        XCTAssertEqual(m.segments[0].key?.iv, Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xAB, 0xCD]))
        XCTAssertNil(m.segments[2].key)
        XCTAssertFalse(m.hasDRM)
    }

    func testLiveAndDRM() throws {
        let live = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXTINF:4,
        a.ts
        """
        guard case .media(let m) = try HLSParser.parse(live, baseURL: base) else { return XCTFail() }
        XCTAssertTrue(m.isLive)

        let drm = """
        #EXTM3U
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://abc",KEYFORMAT="com.apple.streamingkeydelivery"
        #EXTINF:4,
        a.ts
        #EXT-X-ENDLIST
        """
        guard case .media(let d) = try HLSParser.parse(drm, baseURL: base) else { return XCTFail() }
        XCTAssertTrue(d.hasDRM)
    }

    func testRejectsNonPlaylist() {
        XCTAssertThrowsError(try HLSParser.parse("<html></html>", baseURL: base))
    }

    func testDefaultIV() {
        XCTAssertEqual(AES128.iv(sequence: 258), Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2]))
    }

    func testOutputNames() {
        XCTAssertEqual(Output.sanitize("a/b: c?"), "a-b- c")
        XCTAssertEqual(Output.sanitize("  ...  "), "video")
    }
}
