import 'dart:convert';

import 'tag_variant.dart';

sealed class TagMessage {
  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  static TagMessage decode(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    return switch (json['type']) {
      'hello' => HelloMessage.fromJson(json),
      'start' => StartMessage.fromJson(json),
      'tag' => TagEvent.fromJson(json),
      'unfreeze' => UnfreezeEvent.fromJson(json),
      'end' => EndMessage.fromJson(json),
      'tutorial_vote' => TutorialVoteCast.fromJson(json),
      'tutorial_state' => TutorialVoteStateMessage.fromJson(json),
      'tutorial_call' => TutorialVoteCallMessage.fromJson(json),
      _ => throw FormatException('Unknown TagMessage: ${json['type']}'),
    };
  }
}

/// Peer -> host: ask the host to open a tutorial vote.
class TutorialVoteCallMessage extends TagMessage {
  TutorialVoteCallMessage();

  @override
  Map<String, Object?> toJson() => {'type': 'tutorial_call'};

  factory TutorialVoteCallMessage.fromJson(Map<String, Object?> _) =>
      TutorialVoteCallMessage();
}

/// Peer -> host: a yes/no vote in the pre-round tutorial vote.
class TutorialVoteCast extends TagMessage {
  TutorialVoteCast({required this.voterId, required this.yes});
  final String voterId;
  final bool yes;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'tutorial_vote', 'voterId': voterId, 'yes': yes};

  factory TutorialVoteCast.fromJson(Map<String, Object?> j) =>
      TutorialVoteCast(voterId: j['voterId']! as String, yes: j['yes']! as bool);
}

/// Host -> peers: current tutorial vote tally + result.
class TutorialVoteStateMessage extends TagMessage {
  TutorialVoteStateMessage({
    required this.isOpen,
    required this.yesCount,
    required this.noCount,
    required this.eligibleCount,
    required this.result,
    required this.tutorialShown,
  });
  final bool isOpen;
  final int yesCount;
  final int noCount;
  final int eligibleCount;
  final bool? result;
  final bool tutorialShown;

  @override
  Map<String, Object?> toJson() => {
        'type': 'tutorial_state',
        'isOpen': isOpen,
        'yesCount': yesCount,
        'noCount': noCount,
        'eligibleCount': eligibleCount,
        'result': result,
        'tutorialShown': tutorialShown,
      };

  factory TutorialVoteStateMessage.fromJson(Map<String, Object?> j) =>
      TutorialVoteStateMessage(
        isOpen: j['isOpen']! as bool,
        yesCount: (j['yesCount']! as num).toInt(),
        noCount: (j['noCount']! as num).toInt(),
        eligibleCount: (j['eligibleCount']! as num).toInt(),
        result: j['result'] as bool?,
        tutorialShown: j['tutorialShown']! as bool,
      );
}

class HelloMessage extends TagMessage {
  HelloMessage({required this.peerId, required this.displayName});
  final String peerId;
  final String displayName;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'hello', 'peerId': peerId, 'displayName': displayName};

  factory HelloMessage.fromJson(Map<String, Object?> j) =>
      HelloMessage(peerId: j['peerId']! as String, displayName: j['displayName']! as String);
}

class StartMessage extends TagMessage {
  StartMessage({
    required this.variant,
    required this.startingItId,
    required this.startTimeMs,
    required this.peerIds,
    required this.peerNames,
  });

  final TagVariant variant;
  final String startingItId;
  final int startTimeMs;
  final List<String> peerIds;
  final Map<String, String> peerNames;

  @override
  Map<String, Object?> toJson() => {
        'type': 'start',
        'variant': variant.name,
        'startingItId': startingItId,
        'startTimeMs': startTimeMs,
        'peerIds': peerIds,
        'peerNames': peerNames,
      };

  factory StartMessage.fromJson(Map<String, Object?> j) => StartMessage(
        variant: TagVariant.values.byName(j['variant']! as String),
        startingItId: j['startingItId']! as String,
        startTimeMs: j['startTimeMs']! as int,
        peerIds: (j['peerIds']! as List).cast<String>(),
        peerNames: ((j['peerNames'] ?? <String, String>{}) as Map)
            .cast<String, String>(),
      );
}

class TagEvent extends TagMessage {
  TagEvent({required this.taggerId, required this.victimId, required this.timeMs});
  final String taggerId;
  final String victimId;
  final int timeMs;

  @override
  Map<String, Object?> toJson() => {
        'type': 'tag',
        'taggerId': taggerId,
        'victimId': victimId,
        'timeMs': timeMs,
      };

  factory TagEvent.fromJson(Map<String, Object?> j) => TagEvent(
        taggerId: j['taggerId']! as String,
        victimId: j['victimId']! as String,
        timeMs: j['timeMs']! as int,
      );
}

class UnfreezeEvent extends TagMessage {
  UnfreezeEvent({required this.unfreezerId, required this.victimId, required this.timeMs});
  final String unfreezerId;
  final String victimId;
  final int timeMs;

  @override
  Map<String, Object?> toJson() => {
        'type': 'unfreeze',
        'unfreezerId': unfreezerId,
        'victimId': victimId,
        'timeMs': timeMs,
      };

  factory UnfreezeEvent.fromJson(Map<String, Object?> j) => UnfreezeEvent(
        unfreezerId: j['unfreezerId']! as String,
        victimId: j['victimId']! as String,
        timeMs: j['timeMs']! as int,
      );
}

class EndMessage extends TagMessage {
  EndMessage({required this.reason, required this.winnerId});
  final String reason;
  final String? winnerId;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'end', 'reason': reason, 'winnerId': winnerId};

  factory EndMessage.fromJson(Map<String, Object?> j) => EndMessage(
        reason: j['reason']! as String,
        winnerId: j['winnerId'] as String?,
      );
}
