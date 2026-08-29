/// The exact status vocabulary the add_celebrations Edge Function returns.
/// Task 2's Deno test pins it; this enum is the client half of that contract.
/// An unrecognised string maps to [failed] rather than throwing, so a server
/// that grows a new status degrades instead of crashing an import of 500.
enum ImportStatus {
  added,
  duplicate,
  suppressed,
  invalidPhone,
  invalidName,
  self,
  failed;

  static ImportStatus fromWire(String value) => switch (value) {
        'added' => ImportStatus.added,
        'duplicate' => ImportStatus.duplicate,
        'suppressed' => ImportStatus.suppressed,
        'invalid_phone' => ImportStatus.invalidPhone,
        'invalid_name' => ImportStatus.invalidName,
        'self' => ImportStatus.self,
        _ => ImportStatus.failed,
      };
}

class ImportOutcome {
  const ImportOutcome({
    required this.phone,
    required this.personId,
    required this.status,
  });

  final String phone;
  final int? personId;
  final ImportStatus status;

  factory ImportOutcome.fromRow(Map<String, dynamic> row) => ImportOutcome(
        phone: row['phone'] as String,
        personId: row['person_id'] as int?,
        status: ImportStatus.fromWire(row['status'] as String),
      );
}

class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.skipped,
    required this.failed,
    required this.duplicates,
    required this.results,
  });

  final int added;
  final int skipped;
  final int failed;
  final int duplicates;
  final List<ImportOutcome> results;

  ImportSummary merge(ImportSummary other) => ImportSummary(
        added: added + other.added,
        skipped: skipped + other.skipped,
        failed: failed + other.failed,
        duplicates: duplicates + other.duplicates,
        results: [...results, ...other.results],
      );

  static const empty = ImportSummary(
    added: 0,
    skipped: 0,
    failed: 0,
    duplicates: 0,
    results: [],
  );
}
