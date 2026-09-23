/// Advisory capability evidence for a provider model and API surface.
///
/// Descriptors never reject arbitrary model IDs. They record what the SDK has
/// verified for a named model at a dated source, separating documentation
/// evidence from fixtures and authenticated smoke tests.
class ProviderCapabilityDescriptor {
  const ProviderCapabilityDescriptor({
    required this.provider,
    required this.modelId,
    required this.apiSurface,
    required this.source,
    required this.verifiedOn,
    this.maxEmbeddingsPerCall,
    this.supportsParallelCalls,
    this.features = const {},
    this.feature,
    this.lifecycle = ProviderCapabilityLifecycle.stable,
    this.confidence = ProviderCapabilityConfidence.catalog,
    this.evidenceId,
  });

  final String provider;
  final String modelId;
  final String apiSurface;
  final Uri source;
  final DateTime verifiedOn;
  final int? maxEmbeddingsPerCall;
  final bool? supportsParallelCalls;
  final Set<String> features;
  final String? feature;
  final ProviderCapabilityLifecycle lifecycle;
  final ProviderCapabilityConfidence confidence;
  final String? evidenceId;
}

/// Provider lifecycle is independent from the evidence available for a claim.
enum ProviderCapabilityLifecycle { stable, preview, deprecated }

/// Evidence confidence records how a capability was verified.
enum ProviderCapabilityConfidence { catalog, fixture, liveSmoke }
