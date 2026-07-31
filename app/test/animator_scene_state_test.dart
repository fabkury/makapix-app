// SceneState parsing (lib/animator/model/scene_state.dart): the seam-contract fixture must
// parse fully; garbage and missing fields fall back tolerantly (the UI never crashes on
// state_json drift).
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/animator/model/scene_state.dart';

const _fixture = '{"w":48,"h":32,"millifps":25000,"frame_cs":4,"frame_count":40,'
    '"background":"#102030FF","playhead":12,"loop":[5,20],"playing":false,"auto_key":true,'
    '"selected_actor":3,"can_undo":true,"can_redo":false,"cache_epoch":17,"uses_alpha":true,'
    '"cast":[{"id":1,"name":"bird","w":24,"h":16,"frames":3,"cycle":[2,2,2],"cycle_len":6,'
    '"style":"cleanedge","has_semi_alpha":false,"art_epoch":2}],'
    '"actors":[{"id":3,"name":"bird 1","prop":1,"z":0,"mode":"playing","pin_to":null,'
    '"visible":true,'
    '"pose":{"x":10,"y":20,"rot_mdeg":15000,"scale_milli":1500,"opacity":128,"flip_h":true,'
    '"flip_v":false,"pivot_x_milli":12000,"pivot_y_milli":8000,"pose":0},'
    '"bounds":[4,12,40,28],"src_frame":2,'
    '"tracks":{"x":{"base":10,"keys":[{"f":0,"v":10,"tw":"linear"},{"f":24,"v":50,"tw":"hold"}]},'
    '"y":{"base":20,"keys":[]},"rot":{"base":0,"keys":[]},"scale":{"base":1000,"keys":[]},'
    '"flip_h":{"base":0,"keys":[]},"flip_v":{"base":0,"keys":[]},'
    '"opacity":{"base":255,"keys":[{"f":9,"v":128,"tw":"easein"}]},'
    '"pivot_x":{"base":12000,"keys":[]},"pivot_y":{"base":8000,"keys":[]},'
    '"pose":{"base":0,"keys":[]}}}],'
    '"mem_unique_bytes":4096,"mem_table_bytes":8,"mem_budgeted_bytes":4104,'
    '"mem_soft_budget":167772160,"mem_hard_budget":201326592,"mem_soft_exceeded":false,'
    '"mem_refusals":1,"mem_last_refusal":"too big"}';

void main() {
  test('parses the seam-contract fixture completely', () {
    final s = SceneState.parse(_fixture);
    expect((s.w, s.h), (48, 32));
    expect(s.millifps, 25000);
    expect((s.loopA, s.loopB), (5, 20));
    expect(s.selectedActor, 3);
    expect(s.usesAlpha, isTrue);
    expect(s.cast, hasLength(1));
    expect(s.cast.first.cycle, [2, 2, 2]);
    expect(s.cast.first.uniformStep, 2, reason: 'all entries agree');
    expect(s.cast.first.cycleLen, 6);
    expect(s.cast.first.style, 'cleanedge');

    final a = s.selected!;
    expect(a.name, 'bird 1');
    expect(a.pose.rotMdeg, 15000);
    expect(a.pose.flipH, isTrue);
    expect(a.bounds, [4, 12, 40, 28]);
    expect(a.srcFrame, 2);
    expect(a.tracks['x']!.keys, hasLength(2));
    expect(a.tracks['x']!.keys[1].tween, 'hold');
    expect(a.keyFrames(), {0, 24, 9});
    expect(a.hasKeyAt(9), isTrue);
    expect(a.hasKeyAt(10), isFalse);
    expect(s.allKeyFrames(), {0, 24, 9});
    expect(s.memRefusals, 1);
    expect(s.memLastRefusal, 'too big');
  });

  test('garbage and gaps fall back tolerantly', () {
    expect(SceneState.parse('not json').frameCount, greaterThan(0));
    final s = SceneState.parse('{"w":8}');
    expect(s.w, 8);
    expect(s.actors, isEmpty);
    expect(s.selected, isNull);
    // An actor with a missing tracks map still yields all ten (empty) tracks.
    final s2 = SceneState.parse('{"actors":[{"id":1}]}');
    expect(s2.actors.single.tracks.length, kTrackNames.length);
    expect(s2.actors.single.keyFrames(), isEmpty);
  });

  test('cycle list tolerates absence and reports mixed maps', () {
    final s = SceneState.parse('{"cast":[{"id":1,"frames":3,"cycle":[1,2,4]}]}');
    expect(s.cast.single.cycle, [1, 2, 4]);
    expect(s.cast.single.uniformStep, isNull, reason: 'mixed steps have no uniform value');
    final bare = SceneState.parse('{"cast":[{"id":2}]}');
    expect(bare.cast.single.cycle, isEmpty);
    expect(bare.cast.single.uniformStep, isNull);
  });
}
