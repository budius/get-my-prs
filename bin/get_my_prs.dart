import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';

Future<void> main(List<String> arguments) async {
  // date since when get PRs from
  var tempDefaultDate = DateTime.now().add(Duration(days: -1));
  while (tempDefaultDate.weekday != DateTime.sunday) {
    tempDefaultDate = tempDefaultDate.add(Duration(days: -1));
  }
  final defaultDate = '${tempDefaultDate.year}-'
      '${tempDefaultDate.month.toString().padLeft(2, '0')}-'
      '${tempDefaultDate.day.toString().padLeft(2, '0')}';

  // parse the input
  final parser = ArgParser();
  final title = 'Get My PRs usage:';
  parser.addSeparator('\n$title\n${'-' * title.length}');
  parser.addOption('accessToken',
      abbr: 't', help: 'Github personal access token', mandatory: true);
  parser.addOption('projects',
      abbr: 'p',
      help: 'Comma separated list of Github projects',
      mandatory: true);
  parser.addOption('owner',
      abbr: 'o', help: 'Github account owner', mandatory: true);
  parser.addOption('date',
      abbr: 'd',
      help: 'Since which date to get PRs from yyyy-MM-dd',
      defaultsTo: defaultDate);
  parser.addFlag('help', abbr: 'h', help: 'Prints usage', negatable: false);

  final String accessToken;
  final Iterable<String> projects;
  final String owner;
  final String date;
  try {
    final ArgResults args = parser.parse(arguments);
    if (args['help'] == true) {
      print('${parser.usage}\n');
      exit(0);
    }
    accessToken = args['accessToken'];
    projects = (args['projects'] as String).split(',').map((e) => e.trim());
    owner = args['owner'];
    date = args['date'];
  } on ArgumentError catch (e) {
    final msg = e.toString();
    print('\n$msg\n${'*' * msg.length}');
    print('${parser.usage}\n');
    exit(64);
  }

  // config the HTTP client
  final client = http.Client();
  final headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'Authorization': 'Bearer $accessToken'
  };

  try {
    // get the user
    final userUrl = Uri.https('api.github.com', 'user');
    final userResponse = await client.get(userUrl, headers: headers);
    final userJson = jsonDecode(utf8.decode(userResponse.bodyBytes)) as Map;
    final userLogin = userJson['login'];

    // for each project
    final futureResults = projects.map((repo) async {
      // build the search query
      // https://docs.github.com/en/rest/search/search?apiVersion=2022-11-28#search-issues-and-pull-requests
      // https://docs.github.com/en/rest/search/search?apiVersion=2022-11-28#constructing-a-search-query
      final query = [
        // search for PRs (any state)
        'is:pull-request',
        // from this repository
        'repo:$owner/$repo',
        // by "me"
        'author:$userLogin',
        // created since
        'created:>$date'
      ].join(' ');

      // execute search
      final url = Uri.https('api.github.com', 'search/issues',
          {'q': query, 'sort': 'created', 'order': 'asc'});

      final projectResponse = await client.get(url, headers: headers);
      final projectJson =
          jsonDecode(utf8.decode(projectResponse.bodyBytes)) as Map;

      // extract the titles
      return (projectJson['items'] as List<dynamic>)
          .map((e) => e['title'] as String);
    });

    // print the result
    final results = (await Future.wait(futureResults)).flattened;
    final msg = 'Your ${results.length} PRs since $date:';
    print('\n$msg\n${'-' * msg.length}');
    results.forEach(print);
    print('\neof.\n');
  } finally {
    client.close();
  }
}
