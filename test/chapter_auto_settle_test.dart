// 职责: 自动沉淀（纯代码）的回归测试。
// 关联文件: lib/shared/services/chapter_auto_settle.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/chapter_auto_settle.dart';

const String _sampleChapter = '''
　　裴旻推开偏殿的门时，里面只有一盏灯。
　　老仆跪在阶下，手里的铜盆还在滴水。他没抬头，只把一句话丢在青砖上："公子，郎君没了。"
　　裴旻站在门槛上没动。烛火在他脸上晃了一下，又缩回去。
　　他终于开口，声音很轻："谁动的手？"
　　老仆磕了一个头，额头撞在砖上，闷响。他说不出名字，只说出三个字：北门。
　　裴旻转身就走。走到第二进院子，他忽然停下，回头看了一眼那扇门。
　　从这一刻起，他不再是那个惯于低头的人。他决定去北门，哪怕今夜之后再也回不来。
　　院子外面下起了雨。雨点砸在瓦上，像有人在数他的步子。
　　北门的守将姓陈，四十上下，脸上有一道旧疤。他看见裴旻，先笑了，笑得很难看。
　　"你来得比我料想的早。"
　　裴旻没有回话。他把手里的刀放在地上，刀尖朝着对方。
　　陈守将的笑容僵住。他退了一步，脚跟撞到门槛。
　　于是两个人都不说话，只剩雨声。灯笼在风里摇，光影一下一下地扫过湿漉漉的石阶。
　　忽然，裴旻动了一下。不是拔刀，是弯腰。
　　他捡起那把刀，重新插进鞘里，然后抬手，把湿透的外袍脱下来递给旁边发抖的少年兵。
　　"披上。"他说，"今晚冷。"
　　少年兵愣住，手都不知道往哪儿放。
　　陈守将盯着这一幕，喉结动了一下。他忽然意识到，眼前这个人不是来杀他的。
　　裴旻抬头看雨，看了很久，才说："我来问一件事。郎君死那夜，北门谁开的？"
　　陈守将沉默。沉默里有雨，有灯笼，有远处更夫敲过的梆子声。
　　最后他侧过身，让出那条窄门。门后是一条看不见尽头的巷子。
　　"往里走，第七户。"他说，"门是虚掩的。"
　　裴旻从他身边走过去，肩膀几乎擦到他的旧疤。
　　走到第七户门口，裴旻停住。门果然虚掩，缝里透出一点暖黄的光。
　　他没有立刻推门。他站在雨里，把手按在门板上，感觉到里面有人在呼吸。
''';

void main() {
  test('正文达到阈值时产出完整的沉淀数据', () {
    final settlement = settleChapter(
      _sampleChapter,
      knownNames: const <String>['裴旻', '陈守将', '老仆'],
    );

    expect(settlement, isNotNull);
    final result = settlement!;

    expect(result.brief.isNotEmpty, isTrue);
    expect(result.brief.length, greaterThan(60));
    expect(result.selectedSentenceCount, inInclusiveRange(2, 6));
    expect(result.events.length, inInclusiveRange(1, 6));
    expect(result.tension, inInclusiveRange(1, 10));
    expect(result.emotions.isNotEmpty, isTrue);
    expect(result.hook.isNotEmpty, isTrue);
    expect(result.cast, contains('裴旻'));
    expect(result.signature.startsWith('auto_settle.v1'), isTrue);
  });

  test('梗概确实是从正文抽出的句子，不是改写', () {
    final settlement = settleChapter(_sampleChapter);
    expect(settlement, isNotNull);
    expect(briefLooksExtracted(settlement!.brief, _sampleChapter), isTrue);
  });

  test('AI 改写过的梗概不会被判定为自动生成', () {
    const rewritten = '本章写裴旻得知父亲死讯，夜赴北门，与陈守将对峙后获得线索，最终停在第七户门前。';
    expect(briefLooksExtracted(rewritten, _sampleChapter), isFalse);
  });

  test('正文过短时不沉淀', () {
    expect(shouldAutoSettle('裴旻推门进去。'), isFalse);
    expect(settleChapter('裴旻推门进去。'), isNull);
  });

  test('同一份正文结果稳定（确定性）', () {
    final first = settleChapter(_sampleChapter);
    final second = settleChapter(_sampleChapter);
    expect(first!.brief, second!.brief);
    expect(first.signature, second.signature);
    expect(first.tension, second.tension);
  });
}
