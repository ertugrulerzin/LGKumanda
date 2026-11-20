import XCTest

final class DASHTests: XCTestCase {
    func testTemplateExpansion() {
        XCTAssertEqual(DASHParser.expand("v/$RepresentationID$/seg-$Number%05d$.m4s", id: "720p", bandwidth: 1, number: 7, time: nil),
                       "v/720p/seg-00007.m4s")
        XCTAssertEqual(DASHParser.expand("a_$Bandwidth$_$Time$$$.mp4", id: "x", bandwidth: 128000, number: nil, time: 9000),
                       "a_128000_9000$.mp4")
        XCTAssertEqual(DASHParser.duration("PT1H2M3.5S"), 3723.5)
        XCTAssertEqual(DASHParser.duration("P1DT1M"), 86460)
    }

    func testTimelineListAndDRM() throws {
        let mpd = """
        <?xml version="1.0"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT10S">
          <BaseURL>https://cdn.example.com/show/</BaseURL>
          <Period>
            <AdaptationSet contentType="video" mimeType="video/mp4">
              <SegmentTemplate timescale="1000" initialization="$RepresentationID$/init.mp4" media="$RepresentationID$/$Time$.m4s">
                <SegmentTimeline><S t="0" d="4000" r="1"/><S d="2000"/></SegmentTimeline>
              </SegmentTemplate>
              <Representation id="hd" bandwidth="3000000" width="1280" height="720"/>
              <Representation id="sd" bandwidth="800000" width="640" height="360"/>
            </AdaptationSet>
            <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="tr">
              <Representation id="aud" bandwidth="128000">
                <BaseURL>audio.mp4</BaseURL>
                <SegmentList timescale="1" duration="5">
                  <Initialization sourceURL="audio.mp4" range="0-99"/>
                  <SegmentURL mediaRange="100-199"/><SegmentURL mediaRange="200-299"/>
                </SegmentList>
              </Representation>
            </AdaptationSet>
            <AdaptationSet contentType="text" mimeType="text/vtt" lang="en">
              <Representation id="sub" bandwidth="1"><BaseURL>subs/en.vtt</BaseURL></Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """
        let m = try DASHParser.parse(Data(mpd.utf8), url: URL(string: "https://x.com/m.mpd")!)
        XCTAssertFalse(m.isLive)
        XCTAssertFalse(m.hasDRM)
        XCTAssertEqual(m.videos.map(\.id), ["hd", "sd"])
        guard case .segments(let v) = m.videos[0].plan else { return XCTFail() }
        XCTAssertEqual(v.segments.map(\.url.absoluteString), [
            "https://cdn.example.com/show/hd/0.m4s", "https://cdn.example.com/show/hd/4000.m4s", "https://cdn.example.com/show/hd/8000.m4s",
        ])
        XCTAssertEqual(v.totalDuration, 10, accuracy: 0.001)
        XCTAssertEqual(v.initSection?.url.absoluteString, "https://cdn.example.com/show/hd/init.mp4")
        guard case .segments(let a) = m.bestAudio?.plan else { return XCTFail() }
        XCTAssertEqual(a.segments.map(\.byteRange), [HLSByteRange(length: 100, offset: 100), HLSByteRange(length: 100, offset: 200)])
        XCTAssertEqual(a.initSection?.byteRange, HLSByteRange(length: 100, offset: 0))
        XCTAssertEqual(m.subtitleFiles.first?.language, "en")

        let drm = mpd.replacingOccurrences(of: "<SegmentTemplate timescale", with:
            "<ContentProtection schemeIdUri=\"urn:mpeg:dash:mp4protection:2011\" value=\"cenc\"/><SegmentTemplate timescale")
        XCTAssertTrue(try DASHParser.parse(Data(drm.utf8), url: URL(string: "https://x.com/m.mpd")!).hasDRM)
    }
}
