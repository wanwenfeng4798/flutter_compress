# Consumer ProGuard/R8 rules shipped with this plugin, so apps that enable
# minification don't have to work out what flutter_compress_pro needs.
#
# The plugin deliberately keeps this list minimal: it does no name-based
# reflection, no JNI and no serialization, so R8 can shrink it freely. The
# `::class.java` references in the sources are compile-time class literals, which
# R8 already tracks.

# Media3 (Transformer/ExoPlayer) ships its own consumer rules with its artifacts;
# do not duplicate them here — a stale copy is worse than none.
