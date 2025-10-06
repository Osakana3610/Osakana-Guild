import Foundation

struct SynthesisRecipeDefinition: Identifiable, Sendable {
    let id: String
    let parentItemId: String
    let childItemId: String
    let resultItemId: String
}
