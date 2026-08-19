package lsp_codegen

import std.io.{OutputStream, StringWriter}

class CjEmitter {
    private let output: StringWriter<OutputStream>
    private var indentation: Int64 = 0

    CjEmitter(output: OutputStream, private let indentWidth!: Int64 = 4) {
        this.output = StringWriter(output)
    }

    /**
     * Emits newline without indentation
     */
    func newLine(): Unit {
        output.write("\n")
    }

    func block(body: () -> Unit): Unit {
        emit("{")
        newLine()
        indented(body)
        newLine()
        emit("}")
    }

    func indented(body: () -> Unit): Unit {
        indentation++
        body()
        indentation--
    }

    func blockComment(bc: BlockComment): Unit {
        if (bc.lines.isEmpty()) {
            emit("/**/")
            return
        }
        emit("/*")
        newLine()
        for (line in bc.lines) {
            if (line.isEmpty()) {
                emit(" *")
            } else {
                emit(" * ${line}")
            }
            newLine()
        }
        emit(" */")
        newLine()
    }

    func flush(): Unit {
        output.flush()
    }

    private func emit(s: String): Unit {
        let indentBytes = Array<Byte>(indentation * indentWidth, repeat: b' ')
        let ws = unsafe { String.fromUtf8Unchecked(indentBytes) }
        output.write("${ws}${s}")
    }
}

struct BlockComment {
    BlockComment(let lines!: Array<String> = []) {}
}
