/// Podcast RSS 2.0 feed with iTunes tags.
library;

import 'dart:io' show HttpDate;

import 'package:xml/xml.dart';

import 'store.dart';
import 'views.dart';

const itunesNs = 'http://www.itunes.com/dtds/podcast-1.0.dtd';
const atomNs = 'http://www.w3.org/2005/Atom';
const contentNs = 'http://purl.org/rss/1.0/modules/content/';

/// `HH:MM:SS`, the form podcast apps read most reliably.
String itunesDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)}';
}

String buildFeed({
  required Views views,
  required ShowRecord show,
  required List<EpisodeRecord> episodes,
  required DateTime now,
}) {
  // The feed always lists newest first, whatever order the show page uses.
  final items = [...episodes]
    ..sort((a, b) => b.publishAt.compareTo(a.publishAt));
  final cover = views.coverUrl(show);
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'rss',
    attributes: {'version': '2.0'},
    nest: () {
      builder.namespace(itunesNs, 'itunes');
      builder.namespace(atomNs, 'atom');
      builder.namespace(contentNs, 'content');
      builder.element(
        'channel',
        nest: () {
          builder.element('title', nest: show.name);
          builder.element('link', nest: views.showUrl(show));
          builder.element(
            'description',
            nest: show.description.isEmpty ? show.name : show.description,
          );
          builder.element('language', nest: show.language);
          builder.element('generator', nest: 'Earshot (Built with Dartus)');
          builder.element('lastBuildDate', nest: HttpDate.format(now));
          builder.element(
            'atom:link',
            attributes: {
              'href': views.feedUrl(show),
              'rel': 'self',
              'type': 'application/rss+xml',
            },
          );
          if (cover != null) {
            builder.element(
              'image',
              nest: () {
                builder.element('url', nest: cover);
                builder.element('title', nest: show.name);
                builder.element('link', nest: views.showUrl(show));
              },
            );
            builder.element('itunes:image', attributes: {'href': cover});
          }
          builder.element('itunes:author', nest: show.author);
          builder.element(
            'itunes:summary',
            nest: show.description.isEmpty ? show.name : show.description,
          );
          builder.element(
            'itunes:category',
            attributes: {'text': show.category},
          );
          builder.element(
            'itunes:explicit',
            nest: show.explicit ? 'true' : 'false',
          );
          builder.element('itunes:type', nest: 'episodic');
          for (final e in items) {
            builder.element(
              'item',
              nest: () {
                builder.element('title', nest: e.title);
                builder.element(
                  'description',
                  nest: e.description.isEmpty ? e.title : e.description,
                );
                builder.element('link', nest: views.episodeUrl(show, e));
                builder.element(
                  'guid',
                  attributes: {'isPermaLink': 'false'},
                  nest: 'earshot:${show.slug}:${e.id}',
                );
                builder.element('pubDate', nest: HttpDate.format(e.publishAt));
                builder.element(
                  'enclosure',
                  attributes: {
                    'url': views.config.blobUrl(e.blobId).toString(),
                    'length': '${e.sizeBytes}',
                    'type': e.mime,
                  },
                );
                if (e.durationSeconds != null) {
                  builder.element(
                    'itunes:duration',
                    nest: itunesDuration(e.durationSeconds!),
                  );
                }
                builder.element('itunes:episodeType', nest: 'full');
                builder.element(
                  'itunes:explicit',
                  nest: show.explicit ? 'true' : 'false',
                );
              },
            );
          }
        },
      );
    },
  );
  // Pretty-print the structure but keep line breaks inside text, so show
  // notes keep their paragraphs in podcast apps.
  return builder.buildDocument().toXmlString(
    pretty: true,
    indent: '  ',
    preserveWhitespace: (node) =>
        node is XmlElement &&
        node.children.length == 1 &&
        node.children.first is XmlText,
  );
}
