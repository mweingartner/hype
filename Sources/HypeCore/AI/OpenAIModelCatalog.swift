/// Text and image choices discovered together from OpenAI's model catalog.
public struct OpenAIModelCatalog: Sendable, Equatable {
    public let textModels: [String]
    public let imageModels: [String]
}
