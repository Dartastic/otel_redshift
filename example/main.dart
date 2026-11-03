// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_redshift/otel_redshift.dart';

/// Traces Redshift Data calls with OpenTelemetry.
///
/// `otel_redshift` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Redshift Data call in
/// [tracedRedshiftQuery]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'redshift-example');

  // Wraps a Redshift Data API SQL query in a CLIENT span.
  final redshiftQueryId = await tracedRedshiftQuery<String>(
    statement: 'active',
    clusterIdentifier: 'example',
    workgroupName: 'example',
    database: 'example',
    region: 'us-east-1',
    invoke: () async {
      // Make the Redshift Data call here, then report what it returned.
      const id = 'redshift_8f3a2c';
      return const RedshiftQueryResult(
          value: id, queryId: 'query_8f3a2c', rowCount: 3);
    },
  );
  OTelLog.info('tracedRedshiftQuery returned $redshiftQueryId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutRedshiftInstrumentationAsync.
  await runWithoutRedshiftInstrumentationAsync(
    () => tracedRedshiftQuery<String>(
      statement: 'active',
      clusterIdentifier: 'example',
      workgroupName: 'example',
      database: 'example',
      region: 'us-east-1',
      invoke: () async {
        const id = 'redshift_8f3a2c';
        return const RedshiftQueryResult(
            value: id, queryId: 'query_8f3a2c', rowCount: 3);
      },
    ),
  );

  await OTel.shutdown();
}
