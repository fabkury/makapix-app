import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/player_api.dart';
import 'package:makapix_club/club/state/player_providers.dart';

void main() {
  group('PlayerCommand.toJson', () {
    test('show_artwork carries only the post id', () {
      expect(const PlayerCommand.showArtwork(7).toJson(),
          {'command_type': 'show_artwork', 'post_id': 7});
    });

    test('swap commands carry only their type', () {
      expect(const PlayerCommand.swapNext().toJson(), {'command_type': 'swap_next'});
      expect(const PlayerCommand.swapBack().toJson(), {'command_type': 'swap_back'});
    });

    test('null fields are dropped', () {
      final m = const PlayerCommand(commandType: 'play_channel', channelName: 'all').toJson();
      expect(m, {'command_type': 'play_channel', 'channel_name': 'all'});
      expect(m.containsKey('hashtag'), isFalse);
      expect(m.containsKey('user_sqid'), isFalse);
    });
  });

  group('ChannelTarget.toCommand', () {
    test('an explicit channel name is preserved', () {
      final cmd = const ChannelTarget(displayName: 'Recent', channelName: 'all').toCommand();
      expect(cmd.toJson(), {'command_type': 'play_channel', 'channel_name': 'all'});
    });

    test('a hashtag channel sends only the hashtag (no channel_name)', () {
      final cmd = const ChannelTarget(displayName: '#pixel', hashtag: 'pixel').toCommand();
      expect(cmd.toJson(), {'command_type': 'play_channel', 'hashtag': 'pixel'});
    });

    test('a user channel infers by_user from the sqid', () {
      final cmd = const ChannelTarget(
        displayName: 'Fab',
        userSqid: 't5',
        userHandle: 'Fab',
      ).toCommand();
      expect(cmd.toJson(), {
        'command_type': 'play_channel',
        'channel_name': 'by_user',
        'user_sqid': 't5',
        'user_handle': 'Fab',
      });
    });
  });
}
