import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class HighlightIO {
  static void sendLog(String message, Map<String, String> index) {
    var log = jsonEncode({
      'resourceLogs': [
        {
          'resource': {
            'attributes': [
              {
                'key': 'service.name',
                'value': {'stringValue': 'my-service'}
              }
            ]
          },
          'scopeLogs': [
            {
              'scope': {},
              'logRecords': [
                {
                  'timeUnixNano': '${DateTime.now().microsecondsSinceEpoch}000',
                  'severityText': 'Info',
                  'body': {'stringValue': '$message'},
                  'attributes': [
                    {
                      'key': 'highlight.project_id',
                      'value': {'stringValue': '6glrn3mg'}
                    },
                    ...index.entries.map((v) => {
                      'key': v.key,
                      'value': {'stringValue': v.value}
                    }).toList(),
                  ],
                  // 'traceId': '',
                  // 'spanId': '',
                }
              ]
            }
          ]
        }
      ]
    });

    http.post(
      Uri.parse('https://otel.highlight.io:4318/v1/logs'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: log,
    );
    debugPrint(log);
  }
}
