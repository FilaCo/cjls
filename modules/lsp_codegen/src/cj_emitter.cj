package lsp_codegen

import std.ast.*
import std.io.{ByteBuffer, OutputStream, StringWriter, readToEnd}

class CjEmitter {
    private let output: StringWriter<OutputStream>
    private var indentation: Int64 = 0

    CjEmitter(output: OutputStream, private let indentWidth!: Int64 = 4) {
        this.output = StringWriter(output)
    }

    func flush(): Unit {
        output.flush()
    }

    func nl(): Unit {
        output.write("\n")
    }

    func blockln(body: () -> Unit): Unit {
        emitln("{")
        indented(body)
        nl()
        emitln("}")
    }

    func indented(body: () -> Unit): Unit {
        indentation++
        body()
        indentation--
    }

    func emit(dc: DocComment): Unit {
        emitln("/**")
        for (line in dc.lines) {
            if (line.isEmpty()) {
                emit(" *")
            } else {
                emit(" * ${escapedCommentText(line)}")
            }
            nl()
        }
        emit(" */")
    }

    func emitln(dc: DocComment): Unit {
        emit(dc)
        nl()
    }

    func emit(toks: Tokens): Unit {
        emit(toks.toString())
    }

    func emitln(toks: Tokens): Unit {
        emitln(toks.toString())
    }

    func emit(s: String): Unit {
        let indentBytes = Array<Byte>(indentation * indentWidth, repeat: b' ')
        let ws = unsafe { String.fromUtf8Unchecked(indentBytes) }
        output.write("${ws}${s}")
    }

    func emitln(s: String): Unit {
        emit(s)
        nl()
    }
}

/**
 * What `body` has an emitter write.
 */
func emittedBy(body: (CjEmitter) -> Unit): String {
    let output = ByteBuffer()
    let emitter = CjEmitter(output)
    body(emitter)
    emitter.flush()

    unsafe { String.fromUtf8(readToEnd(output)) }
}

struct DocComment {
    DocComment(let lines!: Array<String> = []) {}
}

/**
 * Block comments nest in Cangjie: a glob such as `**` + `/` + `*.ts` in the text opens a comment the
 * doc comment's own closing only ends, and the rest of the file is swallowed.
 */
func escapedCommentText(text: String): String {
    text.replace("/*", "/\\*").replace("*/", "*\\/")
}
