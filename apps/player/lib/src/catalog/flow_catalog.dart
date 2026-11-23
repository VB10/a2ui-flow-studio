import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:flow_compiler/flow_compiler.dart';

import 'photo_picker.dart';
import 'photo_uploader.dart';

/// Our own catalog: every basic component plus `PhotoPicker`.
///
/// The id must match [A2uiDsl.flowCatalogId]: the server puts it in
/// `createSurface.catalogId` whenever a step uses a custom component.
CatalogImplementation flowCatalog({required PhotoUploader uploader}) {
  final basic = basicCatalog();
  return CatalogImplementation(
    id: A2uiDsl.flowCatalogId,
    components: [
      ...basic.components.values,
      photoPickerComponent(uploader),
    ],
    // required, email, length, numeric, and ... stay available.
    functions: basic.functions.values.toList(),
    schemaId: basic.schemaId,
    protocolVersion: basic.protocolVersion,
    definitions: basic.definitions,
  );
}
