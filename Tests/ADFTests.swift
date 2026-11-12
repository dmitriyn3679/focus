import Foundation

let meAccountId = "712020:00000000-0000-0000-0000-000000000001"

func adfMention(_ id: String, _ text: String = "@Test User") -> String {
    #"{"type":"mention","attrs":{"id":"\#(id)","text":"\#(text)","accessLevel":""}}"#
}

func adfText(_ text: String) -> String {
    #"{"type":"text","text":"\#(text)"}"#
}

func adfParagraph(_ nodes: String...) -> String {
    #"{"type":"paragraph","content":[\#(nodes.joined(separator: ","))]}"#
}

func adfDoc(_ nodes: String...) -> String {
    #"{"type":"doc","version":1,"content":[\#(nodes.joined(separator: ","))]}"#
}

private func decodeADF(_ json: String) throws -> ADFNode {
    try JSONDecoder().decode(ADFNode.self, from: Data(json.utf8))
}

func runADFTests() async {
    test("ADF: mention of owner in paragraph") {
        let doc = try decodeADF(adfDoc(adfParagraph(adfText("Waiting for recheck from "), adfMention(meAccountId), adfText(" please"))))
        expectEqual(doc.mentions(accountId: meAccountId), true)
        expectEqual(doc.plainText, "Waiting for recheck from @Test User please")
    }

    test("ADF: mention of another user") {
        let doc = try decodeADF(adfDoc(adfParagraph(adfText("Waiting for recheck from "), adfMention("5c0000000000000000000002"), adfText(" please"))))
        expectEqual(doc.mentions(accountId: meAccountId), false)
    }

    test("ADF: mention nested in a list") {
        let json = adfDoc(#"{"type":"bulletList","content":[{"type":"listItem","content":[\#(adfParagraph(adfMention(meAccountId)))]}]}"#)
        expectEqual(try decodeADF(json).mentions(accountId: meAccountId), true)
    }

    test("ADF: mention nested in a table") {
        let json = adfDoc(#"{"type":"table","attrs":{"isNumberColumnEnabled":false,"layout":"default"},"content":[{"type":"tableRow","content":[{"type":"tableCell","attrs":{},"content":[\#(adfParagraph(adfMention(meAccountId)))]}]}]}"#)
        expectEqual(try decodeADF(json).mentions(accountId: meAccountId), true)
    }

    test("ADF: unknown nodes and non-string attrs") {
        let json = adfDoc(
            #"{"type":"mediaSingle","attrs":{"width":557,"layout":"align-start"},"content":[{"type":"media","attrs":{"id":5,"type":"file"}}]}"#,
            #"{"type":"somethingNew"}"#
        )
        let doc = try decodeADF(json)
        expectEqual(doc.mentions(accountId: meAccountId), false)
        expectEqual(doc.plainText, "")
    }

    test("ADF: paragraphs separated by one space") {
        let doc = try decodeADF(adfDoc(adfParagraph(adfText("a")), adfParagraph(adfText("b"))))
        expectEqual(doc.plainText, "a b")
    }

    test("ADF: hard break becomes a space") {
        let doc = try decodeADF(adfDoc(adfParagraph(adfText("a"), #"{"type":"hardBreak"}"#, adfText("b"))))
        expectEqual(doc.plainText, "a b")
    }
}
