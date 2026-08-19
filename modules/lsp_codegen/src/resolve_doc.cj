package lsp_codegen

struct DocIr {
    DocIr(
        let documentation!: ?String = None,
        let since!: ?String = None,
        let sinceTags!: ?Array<String> = None,
        let proposed!: Bool = false,
        let deprecated!: ?String = None
    ) {}
}

func resolveDoc(enumeration: Enumeration): DocIr {
    docOf(
        documentation: enumeration.documentation,
        since: enumeration.since,
        sinceTags: enumeration.sinceTags,
        proposed: enumeration.proposed,
        deprecated: enumeration.deprecated
    )
}

private func docOf(documentation!: ?String, since!: ?String, sinceTags!: ?Array<String>, proposed!: ?Bool,
    deprecated!: ?String): DocIr {
    DocIr(documentation: documentation, since: since, sinceTags: sinceTags, proposed: proposed ?? false,
        deprecated: deprecated)
}
