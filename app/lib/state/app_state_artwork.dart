part of 'app_state.dart';

/// Emby/Jellyfin/EmbyGo artwork resolution chain backed by the local Rust image proxy.
extension VedroAppStateArtwork on VedroAppState {
  // ---------------------------------------------------------------------------
  // Artwork resolution (exact embygo Web ancestor fallback chain + RAM proxy)
  // ---------------------------------------------------------------------------

  String buildImageUrl(
    String itemId, {
    String type = 'Primary',
    String? tag,
    int? maxWidth,
  }) {
    if (connectedUrl == null || itemId.isEmpty) return '';
    final params = <String>[];
    if (tag != null && tag.isNotEmpty) params.add('tag=${Uri.encodeComponent(tag)}');
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    params.add('quality=88');
    final q = params.isEmpty ? '' : '?${params.join('&')}';
    final encType = type.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');

    if (proxyAddr != null && proxyAddr!.isNotEmpty) {
      return 'http://$proxyAddr/img/Items/${Uri.encodeComponent(itemId)}/Images/$encType$q';
    }
    final base = connectedUrl!.endsWith('/')
        ? connectedUrl!.substring(0, connectedUrl!.length - 1)
        : connectedUrl!;
    return '$base/Items/${Uri.encodeComponent(itemId)}/Images/$encType$q';
  }

  /// Build artwork URL for a specific server (used in multi-server aggregated search).
  String buildServerImageUrl(
    String serverId,
    String itemId, {
    String type = 'Primary',
    String? tag,
    int? maxWidth,
  }) {
    if (itemId.isEmpty) return '';
    final params = <String>[];
    if (tag != null && tag.isNotEmpty) params.add('tag=${Uri.encodeComponent(tag)}');
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    params.add('quality=86');
    final q = params.isEmpty ? '' : '?${params.join('&')}';
    final encType = type.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    if (proxyAddr != null && proxyAddr!.isNotEmpty && serverId.isNotEmpty) {
      return 'http://$proxyAddr/img-srv/${Uri.encodeComponent(serverId)}/Items/${Uri.encodeComponent(itemId)}/Images/$encType$q';
    }
    return buildImageUrl(itemId, type: type, tag: tag, maxWidth: maxWidth);
  }

  String? posterArtUrl(MediaItemModel item, {int width = 420}) {
    if (item.primaryImageTag != null && item.type != 'Episode') {
      return buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width);
    }
    if (item.parentPrimaryImageItemId != null && item.parentPrimaryImageTag != null) {
      return buildImageUrl(
        item.parentPrimaryImageItemId!,
        type: 'Primary',
        tag: item.parentPrimaryImageTag,
        maxWidth: width,
      );
    }
    if (item.seriesId != null && item.seriesPrimaryImageTag != null) {
      return buildImageUrl(
        item.seriesId!,
        type: 'Primary',
        tag: item.seriesPrimaryImageTag,
        maxWidth: width,
      );
    }
    if (item.primaryImageTag != null) {
      return buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width);
    }
    return null;
  }

  /// Direct server-side library cover for `CollectionFolder` / `UserView` items.
  /// Emby / Jellyfin / embygo store generated or custom 16:9 library covers in `Primary`,
  /// `Backdrop`, or `Thumb` on the view item itself.
  String? libraryCoverUrl(MediaItemModel view, {int width = 720}) {
    if (view.primaryImageTag != null && view.primaryImageTag!.isNotEmpty) {
      return buildImageUrl(view.id, type: 'Primary', tag: view.primaryImageTag, maxWidth: width);
    }
    if (view.backdropImageTag != null && view.backdropImageTag!.isNotEmpty) {
      return buildImageUrl(view.id, type: 'Backdrop', tag: view.backdropImageTag, maxWidth: width);
    }
    if (view.thumbImageTag != null && view.thumbImageTag!.isNotEmpty) {
      return buildImageUrl(view.id, type: 'Thumb', tag: view.thumbImageTag, maxWidth: width);
    }
    return null;
  }

  ResolvedArt? wideArt(MediaItemModel item, {int width = 640}) {
    if ((item.type == 'CollectionFolder' || item.type == 'UserView') &&
        item.primaryImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.thumbImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Thumb', tag: item.thumbImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.type == 'Episode' && item.primaryImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.backdropImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Backdrop', tag: item.backdropImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.parentThumbItemId != null && item.parentThumbImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(
          item.parentThumbItemId!,
          type: 'Thumb',
          tag: item.parentThumbImageTag,
          maxWidth: width,
        ),
        isPoster: false,
      );
    }
    if (item.parentBackdropItemId != null && item.parentBackdropImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(
          item.parentBackdropItemId!,
          type: 'Backdrop',
          tag: item.parentBackdropImageTag,
          maxWidth: width,
        ),
        isPoster: false,
      );
    }
    final poster = posterArtUrl(item, width: (width * 0.6).round());
    return poster != null
        ? ResolvedArt(
            url: poster,
            isPoster: true,
            tinyUrl: posterArtUrl(item, width: 140),
          )
        : null;
  }

  ResolvedArt? backdropArt(MediaItemModel item, {int width = 1920}) {
    if (item.backdropImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Backdrop', tag: item.backdropImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.parentBackdropItemId != null && item.parentBackdropImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(
          item.parentBackdropItemId!,
          type: 'Backdrop',
          tag: item.parentBackdropImageTag,
          maxWidth: width,
        ),
        isPoster: false,
      );
    }
    if (item.thumbImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Thumb', tag: item.thumbImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.parentThumbItemId != null && item.parentThumbImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(
          item.parentThumbItemId!,
          type: 'Thumb',
          tag: item.parentThumbImageTag,
          maxWidth: width,
        ),
        isPoster: false,
      );
    }
    if (item.type == 'Episode' && item.primaryImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    final poster = posterArtUrl(item, width: 800);
    return poster != null
        ? ResolvedArt(
            url: poster,
            isPoster: true,
            tinyUrl: posterArtUrl(item, width: 140),
          )
        : null;
  }

  String? logoArtUrl(MediaItemModel item, {int width = 640}) {
    if (item.logoImageTag != null) {
      return buildImageUrl(item.id, type: 'Logo', tag: item.logoImageTag, maxWidth: width);
    }
    if (item.parentLogoItemId != null && item.parentLogoImageTag != null) {
      return buildImageUrl(
        item.parentLogoItemId!,
        type: 'Logo',
        tag: item.parentLogoImageTag,
        maxWidth: width,
      );
    }
    return null;
  }
}
