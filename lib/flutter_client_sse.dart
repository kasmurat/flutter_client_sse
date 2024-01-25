library flutter_client_sse;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';

part 'sse_event_model.dart';

class SSEClient {
  static HttpClient getClient({required bool ignoreBadCertificate}) {
    if (ignoreBadCertificate)
      return HttpClient()..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    else
      return HttpClient();
  }

  static late HttpClient _client;

  /// def: Subscribes to SSE
  /// param:
  /// [method]->Request method ie: GET/POST
  /// [url]->URl of the SSE api
  /// [header]->Map<String,String>, key value pair of the request header
  static Stream<SSEModel> subscribeToSSE({
    required SSERequestType method,
    required String url,
    required Map<String, String> header,
    Map<String, dynamic>? body,
    bool ignoreBadCertificate = false,
  }) {
    // ignore: close_sinks
    StreamController<SSEModel> streamController = StreamController();
    print("Subscribing to server with SSE");
    while (true) {
      try {
        _client = getClient(ignoreBadCertificate: ignoreBadCertificate);

        if (method == SSERequestType.GET) {
          _client.getUrl(Uri.parse(url)).then((request) {
            handleRequest(request, header, body, streamController);
          }, onError: (e, st) {
            streamController.addError(e, st);
          });
        } else {
          _client.postUrl(Uri.parse(url)).then((request) {
            handleRequest(request, header, body, streamController);
          }, onError: (e, st) {
            streamController.addError(e, st);
          });
        }
      } catch (e, st) {
        print(e);
        print(st);
        streamController.addError(e, st);
      }

      return streamController.stream;
    }
  }

  static void unsubscribeFromSSE() {
    _client.close();
  }

  static void handleRequest(
    HttpClientRequest request,
    Map<String, String> header,
    Map<String, dynamic>? body,
    StreamController<SSEModel> streamController,
  ) async {
    var lineRegex = RegExp(r'^([^:]*)(?::)?(?: )?(.*)?$');
    var currentSSEModel = SSEModel(data: '', id: '', event: '');
    // Add header
    header.forEach((key, value) {
      request.headers.add(key, value);
    });

    // Add body
    if (body != null) {
      request.write(jsonEncode(body));
    }

    Future<HttpClientResponse> response = request.close();

    ///Listening to the response as a stream
    response.asStream().listen((data) {
      ///Applying transforms and listening to it
      data
        ..transform(Utf8Decoder()).transform(LineSplitter()).listen(
          (dataLine) {
            if (dataLine.isEmpty) {
              ///This means that the complete event set has been read.
              ///We then add the event to the stream
              streamController.add(currentSSEModel);
              currentSSEModel = SSEModel(data: '', id: '', event: '');
              return;
            }

            ///Get the match of each line through the regex
            Match match = lineRegex.firstMatch(dataLine)!;
            var field = match.group(1);
            if (field!.isEmpty) {
              return;
            }
            var value = '';
            if (field == 'data') {
              //If the field is data, we get the data through the substring
              value = dataLine.substring(5);
            } else {
              value = match.group(2) ?? '';
            }
            switch (field) {
              case 'event':
                currentSSEModel.event = value;
                break;
              case 'data':
                currentSSEModel.data = (currentSSEModel.data ?? '') + value + '\n';
                break;
              case 'id':
                currentSSEModel.id = value;
                break;
              case 'retry':
                break;
            }
          },
          onError: (e, st) {
            print(e);
            print(st);
            streamController.addError(e, st);
          },
        );
    }, onError: (e, st) {
      print(e);
      print(st);
      streamController.addError(e, st);
    });
  }
}
