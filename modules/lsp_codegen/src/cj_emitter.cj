package lsp_codegen

import std.ast.*
import std.collection.HashSet
import std.io.{OutputStream, StringWriter}

class CjEmitter {
    private let output: StringWriter<OutputStream>
    private var indentation: Int64 = 0

    CjEmitter(output: OutputStream, private let indentWidth!: Int64 = 4) {
        this.output = StringWriter(output)
    }

    func flush(): Unit {
        output.flush()
    }

    /**
     * Emits newline without indentation
     */
    func nl(): Unit {
        output.write("\n")
    }

    func block(body: () -> Unit): Unit {
        emitln("{")
        indentedln(body)
        emit("}")
    }

    func blockln(body: () -> Unit): Unit {
        block(body)
        nl()
    }

    func indented(body: () -> Unit): Unit {
        indentation++
        body()
        indentation--
    }

    func indentedln(body: () -> Unit): Unit {
        indented(body)
        nl()
    }

    func emit(dc: DocComment): Unit {
        emitln("/**")
        for (line in dc.lines) {
            if (line.isEmpty()) {
                emit(" *")
            } else {
                emit(" * ${line}")
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

    private func emit(s: String): Unit {
        let indentBytes = Array<Byte>(indentation * indentWidth, repeat: b' ')
        let ws = unsafe { String.fromUtf8Unchecked(indentBytes) }
        output.write("${ws}${s}")
    }

    private func emitln(s: String): Unit {
        emit(s)
        nl()
    }
}

struct DocComment {
    DocComment(let lines!: Array<String> = []) {}
}
