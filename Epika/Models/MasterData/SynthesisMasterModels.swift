import Foundation

struct SynthesisRecipeDefinition: Identifiable, Sendable {
    let id: UInt16
    let parentItemId: UInt16
    let childItemId: UInt16
    let resultItemId: UInt16
}
