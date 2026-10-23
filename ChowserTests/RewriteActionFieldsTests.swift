import Foundation
import Testing
@testable import Chowser

@Suite(.serialized)
@MainActor
struct RewriteActionFieldsTests {
    @Test("Rewrite action controls preserve every supported transformation in execution order")
    func actionFieldsRoundTrip() {
        let actions: [URLRewriteAction] = [
            .forceScheme("https"), .replaceHost("docs.example"),
            .stripQueryParameters(["track", "ref"]), .stripQueryParameterPrefixes(["utm_", "lab_"]),
            .setQueryParameter(name: "mode", value: "safe"), .removeFragment,
        ]
        #expect(RewriteActionFieldsState.derive(from: actions).buildActions() == actions)
        var fields = RewriteActionFieldsState()
        fields.replaceHostEnabled = true
        fields.replaceHost = " "
        fields.stripParamNames = " one, , two "
        fields.stripParamPrefixes = " test_, "
        fields.setParamName = " "
        #expect(fields.buildActions() == [.stripQueryParameters(["one", "two"]), .stripQueryParameterPrefixes(["test_"])])
        #expect(RewriteSchemeFilter(schemes: []).schemes == [])
        #expect(RewriteSchemeFilter(schemes: ["http"]).schemes == ["http"])
        #expect(RewriteSchemeFilter(schemes: ["https"]).schemes == ["https"])
    }

}
