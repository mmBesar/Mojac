import 'package:flutter_test/flutter_test.dart';
import 'package:mojac/data/models.dart';

void main() {
  const channel = Channel(
    id: 'source_1',
    sourceId: 'source',
    name: 'One',
    number: '1',
    url: 'https://example.com/one',
  );

  Programme programme(
    String title,
    int startHour,
    int startMinute,
    int endHour,
    int endMinute,
  ) {
    return Programme(
      channelId: channel.id,
      start: DateTime(2026, 11, 1, startHour, startMinute),
      stop: DateTime(2026, 11, 1, endHour, endMinute),
      title: title,
    );
  }

  // Sorted by start, exactly like XmltvParser and the on-disk cache produce.
  final epg = EpgData.fromMap(<String, List<Programme>>{
    channel.id: <Programme>[
      programme('A', 10, 0, 11, 0),
      programme('B', 11, 0, 12, 0),
      programme('C', 12, 0, 12, 10),
      programme('D', 12, 10, 13, 0),
    ],
  });

  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 11, 1, hour, minute);

  test('nowFor finds the live programme around every boundary', () {
    expect(epg.nowFor(channel, at(9, 59)), isNull);
    expect(epg.nowFor(channel, at(10))?.title, 'A');
    expect(epg.nowFor(channel, at(10, 59))?.title, 'A');
    expect(epg.nowFor(channel, at(11))?.title, 'B');
    // A ten-minute programme still counts as live inside that minute.
    expect(epg.nowFor(channel, at(12, 5))?.title, 'C');
    expect(epg.nowFor(channel, at(13)), isNull);
  });

  test('nextFor returns the following programme, then null', () {
    expect(epg.nextFor(channel, at(9))?.title, 'A');
    expect(epg.nextFor(channel, at(10, 30))?.title, 'B');
    expect(epg.nextFor(channel, at(11))?.title, 'C');
    expect(epg.nextFor(channel, at(12, 5))?.title, 'D');
    expect(epg.nextFor(channel, at(13)), isNull);
  });

  test('forWindow keeps overlapping blocks and drops the rest', () {
    final overlap = epg.forWindow(channel, at(10, 30), at(11, 30));
    expect(overlap.map((item) => item.title), <String>['A', 'B']);

    final short = epg.forWindow(channel, at(12, 5), at(12, 8));
    expect(short.map((item) => item.title), <String>['C']);

    expect(epg.forWindow(channel, at(9), at(9, 30)), isEmpty);
    expect(epg.forWindow(channel, at(13), at(14)), isEmpty);
  });

  test('queries on an empty channel are safe', () {
    const empty = Channel(
      id: 'source_2',
      sourceId: 'source',
      name: 'Two',
      number: '2',
      url: 'https://example.com/two',
    );
    expect(epg.nowFor(empty, at(10)), isNull);
    expect(epg.nextFor(empty, at(10)), isNull);
    expect(epg.forWindow(empty, at(9), at(11)), isEmpty);
  });
}
