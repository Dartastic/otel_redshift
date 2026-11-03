// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

import 'otel_redshift_suppression.dart';

const _tracerName = 'dartastic_otel_libs_redshift';

APITracer _tracer() => OTelAPI.tracerProvider().getTracer(_tracerName);

const _maxStatementLength = 1024;
String _truncate(String s) =>
    s.length <= _maxStatementLength ? s : s.substring(0, _maxStatementLength);

/// Pair returned from `tracedRedshiftQuery` callback.
class RedshiftQueryResult<T> {
  /// Creates a result.
  const RedshiftQueryResult({
    required this.value,
    this.queryId,
    this.rowCount,
  });

  /// The value returned to the caller.
  final T value;
  final String? queryId;
  final int? rowCount;
}

/// Wraps a Redshift Data API SQL query in a CLIENT span. db.system
/// is `redshift` (Postgres-compatible wire protocol, but with
/// Redshift-specific behavior).
Future<T> tracedRedshiftQuery<T>({
  required String statement,
  required Future<RedshiftQueryResult<T>> Function() invoke,
  String? clusterIdentifier,
  String? workgroupName,
  String? database,
  String? region,
}) async {
  if (redshiftInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'db.system': 'redshift',
    'db.operation': _operationFromStatement(statement) ?? 'query',
    'db.statement': _truncate(statement),
  };
  if (database != null) m['db.name'] = database;
  if (clusterIdentifier != null) {
    m['aws.redshift.cluster.identifier'] = clusterIdentifier;
  }
  if (workgroupName != null) m['aws.redshift.workgroup'] = workgroupName;
  if (region != null) m['cloud.region'] = region;

  final span = _tracer().startSpan(
    'redshift ${m['db.operation']}',
    kind: SpanKind.client,
    attributes: OTelAPI.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.queryId != null) {
      extras.add(OTelAPI.attributeString('aws.redshift.query.id', r.queryId!));
    }
    if (r.rowCount != null) {
      extras.add(OTelAPI.attributeInt('db.row_count', r.rowCount!));
    }
    if (extras.isNotEmpty) span.addAttributes(OTelAPI.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTelAPI.attributes([
      OTelAPI.attributeString(
        ErrorAttributes.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

String? _operationFromStatement(String statement) {
  final trimmed = statement.trimLeft();
  if (trimmed.isEmpty) return null;
  final first = trimmed.split(RegExp(r'\s+')).first.toUpperCase();
  const known = {
    'SELECT',
    'INSERT',
    'UPDATE',
    'DELETE',
    'CREATE',
    'ALTER',
    'DROP',
    'TRUNCATE',
    'COPY',
    'UNLOAD',
    'MERGE',
    'WITH',
    'VACUUM',
    'ANALYZE',
  };
  return known.contains(first) ? first : null;
}
