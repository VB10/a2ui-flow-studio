/// JSON schemas of the components our own catalog adds on top of the basic
/// catalog.
///
/// Pure Dart maps, no a2ui_core dependency: the Player wraps them in a
/// `ComponentImplementation` (with a Flutter builder) and the tests wrap them
/// in a `ComponentApi`, so both validate against the exact same contract.
abstract final class FlowCatalogSchemas {
  /// `PhotoPicker`: lets the user pick a photo. `value` is bound to an
  /// `/answers/<key>` path and holds the uploaded path, e.g.
  /// `/uploads/p_abc123.jpg`.
  static const Map<String, Object?> photoPicker = {
    'type': 'object',
    'allOf': [
      {r'$ref': r'common_types.json#/$defs/Checkable'},
      {
        'type': 'object',
        'properties': {
          'component': {'const': 'PhotoPicker'},
          'label': {
            r'$ref': r'common_types.json#/$defs/DynamicString',
            'description': 'Text shown next to the picker.',
          },
          'value': {
            r'$ref': r'common_types.json#/$defs/DynamicString',
            'description':
                'Uploaded photo path. Bind it to /answers/<key> so the '
                'picker can write the path back.',
          },
        },
        'required': ['component', 'value'],
      },
    ],
  };
}
