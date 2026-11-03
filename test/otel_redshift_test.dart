// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_redshift/otel_redshift.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_redshift-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('SELECT records CLIENT span', () async {
    await tracedRedshiftQuery<String>(
      statement: 'SELECT COUNT(*) FROM orders',
      clusterIdentifier: 'analytics-prod',
      database: 'dev',
      region: 'us-east-1',
      invoke: () async => const RedshiftQueryResult(
        value: 'rows',
        queryId: 'q-1',
        rowCount: 1,
      ),
    );
    final a = attrsOf(spans.findSpanByName('redshift SELECT')!);
    expect(a['db.system'], 'redshift');
    expect(a['db.operation'], 'SELECT');
    expect(a['db.name'], 'dev');
    expect(a['aws.redshift.cluster.identifier'], 'analytics-prod');
    expect(a['cloud.region'], 'us-east-1');
    expect(a['aws.redshift.query.id'], 'q-1');
    expect(a['db.row_count'], 1);
  });

  test('serverless workgroup recorded', () async {
    await tracedRedshiftQuery<String>(
      statement: 'COPY x FROM s3://bucket/key',
      workgroupName: 'default-workgroup',
      invoke: () async => const RedshiftQueryResult(value: 'v'),
    );
    final a = attrsOf(spans.findSpanByName('redshift COPY')!);
    expect(a['db.operation'], 'COPY');
    expect(a['aws.redshift.workgroup'], 'default-workgroup');
  });

  test('suppression skips spans', () async {
    await runWithoutRedshiftInstrumentationAsync(() async {
      await tracedRedshiftQuery<String>(
        statement: 'SELECT 1',
        invoke: () async => const RedshiftQueryResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('redshift '), isEmpty);
  });
}
