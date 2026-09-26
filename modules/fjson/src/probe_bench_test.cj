package fjson

import std.unittest.*
import std.unittest.testmacro.*

var probeSink = 0
let PROBE_READER = FjReader(Array<Byte>())
let PROBE_URI: Array<Byte> = ##""file:///home/user/project/src/main.cj""##.toArray()
let PROBE_INT: Array<Byte> = "120".toArray()

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class FjProbeBench {
    @Bench
    func keystrokeSkipOnly(): Unit {
        PROBE_READER.reset(KEYSTROKE)
        PROBE_READER.skipValue()
        probeSink += PROBE_READER.position
    }

    @Bench
    func keystrokeFull(): Unit {
        PROBE_READER.reset(KEYSTROKE)
        probeSink += rpcRead(PROBE_READER, rpcDidChange)[1].changes.size
    }

    @Bench
    func keystrokeEnvelopeOnly(): Unit {
        PROBE_READER.reset(KEYSTROKE)
        probeSink += rpcRead(PROBE_READER, {_: String, r: FjReader => r.skipValue(); 0})[1]
    }

    @Bench
    func readString40(): Unit {
        PROBE_READER.reset(PROBE_URI)
        probeSink += PROBE_READER.readString().size
    }

    @Bench
    func readInt3(): Unit {
        PROBE_READER.reset(PROBE_INT)
        probeSink += PROBE_READER.readInt64()
    }
}
