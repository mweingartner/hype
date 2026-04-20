import Foundation

// MARK: - WebAssetProviderRegistry

/// Central registry that maps `WebAssetSearchProvider` values to their
/// concrete `WebAssetSearchClient` implementations.
///
/// `WebAssetSearchClientFactory.make(provider:)` is the primary entry point;
/// this registry exists as a named gateway so tests and higher-level callers
/// can reference it by name without importing the factory directly.
public enum WebAssetProviderRegistry {

    /// Return a client for the currently selected provider.
    ///
    /// - Parameter provider: The provider to instantiate.
    /// - Returns: A `WebAssetSearchClient` backed by the given provider.
    public static func client(
        for provider: WebAssetSearchProvider,
        sessionFactory: WebAssetURLSessionFactory = .init()
    ) -> any WebAssetSearchClient {
        WebAssetSearchClientFactory.make(
            provider: provider,
            sessionFactory: sessionFactory
        )
    }

    /// All available providers in display order.
    public static var allProviders: [WebAssetSearchProvider] {
        WebAssetSearchProvider.allCases
    }
}
