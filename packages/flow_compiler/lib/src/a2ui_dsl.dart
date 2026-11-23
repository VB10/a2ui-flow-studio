/// Pure Dart A2UI v1.0 DSL helpers.
///
/// Centralizes protocol constants (such as the `checks` validation key,
/// `@path`, `@call`, and basic catalog URI) in a single place so that any
/// upstream protocol adjustments remain isolated here.
abstract final class A2uiDsl {
  /// Protocol version string on the wire for A2UI v1.0.
  static const String protocolVersion = '1.0';

  /// Official A2UI v1.0 Basic Catalog ID.
  static const String basicCatalogId =
      'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json';

  /// Our own catalog: every basic component plus `PhotoPicker`.
  ///
  /// The Player registers a catalog with this exact id. A surface that needs
  /// a custom component must be created with this id, or the Player will not
  /// know the component.
  static const String flowCatalogId =
      'https://au2ui.local/catalogs/flow/v1/catalog.json';

  /// Custom component names that only exist in [flowCatalogId].
  static const Set<String> flowCatalogComponents = {'PhotoPicker'};

  /// Validation key read by `a2ui_core: 0.7.0`.
  static const String checksKey = 'checks';

  /// Data binding reference (`{"@path": path}`).
  static Map<String, Object?> path(String jsonPointer) => {
        '@path': jsonPointer,
      };

  /// Function call reference (`{"@call": name, "args": args}`).
  static Map<String, Object?> call(
    String name, [
    Map<String, Object?>? args,
  ]) =>
      {
        '@call': name,
        if (args != null && args.isNotEmpty) 'args': args,
      };

  /// Single check rule (`{"condition": condition, "message": message}`).
  static Map<String, Object?> checkRule({
    required Map<String, Object?> condition,
    required String message,
  }) =>
      {
        'condition': condition,
        'message': message,
      };

  /// `required` function call on a bound path.
  static Map<String, Object?> requiredCall(String boundPath) => call(
        'required',
        {'value': path(boundPath)},
      );

  /// `email` function call on a bound path.
  static Map<String, Object?> emailCall(String boundPath) => call(
        'email',
        {'value': path(boundPath)},
      );

  /// `length` function call on a bound path.
  static Map<String, Object?> lengthCall(
    String boundPath, {
    int? min,
    int? max,
  }) =>
      call('length', {
        'value': path(boundPath),
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      });

  /// `numeric` function call on a bound path.
  static Map<String, Object?> numericCall(
    String boundPath, {
    num? min,
    num? max,
  }) =>
      call('numeric', {
        'value': path(boundPath),
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      });

  /// Combines boolean conditions with `and` when 2 or more exist.
  ///
  /// Section 5.4 rule 2: `and` requires at least 2 items (`minItems: 2`).
  /// If there is only 1 condition, returns it directly without wrapping in `and`.
  /// If empty, returns `null`.
  static Map<String, Object?>? combineConditionsWithAnd(
    List<Map<String, Object?>> conditions,
  ) {
    if (conditions.isEmpty) return null;
    if (conditions.length == 1) return conditions.first;
    return call('and', {'values': conditions});
  }

  /// Envelope: `deleteSurface`.
  static Map<String, Object?> deleteSurface(String surfaceId) => {
        'version': protocolVersion,
        'deleteSurface': {
          'surfaceId': surfaceId,
        },
      };

  /// Envelope: `createSurface`.
  static Map<String, Object?> createSurface({
    required String surfaceId,
    required Map<String, Object?> dataModel,
    bool sendDataModel = true,
    String catalogId = basicCatalogId,
  }) =>
      {
        'version': protocolVersion,
        'createSurface': {
          'surfaceId': surfaceId,
          'catalogId': catalogId,
          'sendDataModel': sendDataModel,
          'dataModel': dataModel,
        },
      };

  /// Envelope: `updateComponents`.
  static Map<String, Object?> updateComponents({
    required String surfaceId,
    required List<Map<String, Object?>> components,
  }) =>
      {
        'version': protocolVersion,
        'updateComponents': {
          'surfaceId': surfaceId,
          'components': components,
        },
      };

  /// Envelope: `updateDataModel`.
  static Map<String, Object?> updateDataModel({
    required String surfaceId,
    required String path,
    required Object? value,
  }) =>
      {
        'version': protocolVersion,
        'updateDataModel': {
          'surfaceId': surfaceId,
          'path': path,
          'value': value,
        },
      };
}

