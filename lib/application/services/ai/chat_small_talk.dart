import 'dart:convert';
import 'ai_guardrails.dart';
import 'chat_policy.dart';
import 'model_runtime.dart';
import 'ai_conversation.dart';
import 'chat_debug.dart';
import 'chat_scope.dart';
import 'chat_help_catalog.dart';

/// Social response generation has no data tools or verified financial evidence.
/// Previous turns are context only. Routing is separate from reply writing.
class ChatSmallTalk {
  static Future<String?> reply(
    ModelRuntime runtime,
    String message, {
    List<Map<String, dynamic>> history = const [],
    ChatDebug? debug,
    bool interpretedSocial = false,
    void Function(String reason)? onRejected,
  }) async {
    if (ChatPolicy.unsafeOrAdviceReply(message) != null) {
      debug?.log('response_rejected', {
        'stage': 'social',
        'reason': 'input_policy',
      });
      return null;
    }
    final purpose = ChatScope.conversation(message, history);
    if (!interpretedSocial &&
        (purpose == null || purpose == ConversationPurpose.boundary)) {
      debug?.log('response_rejected', {
        'stage': 'social',
        'reason': 'no_current_message_scope',
      });
      return null;
    }
    try {
      // A courtesy or assistant-wellbeing question needs no earlier topics.
      // Actual conversation references retain the bounded successful dialogue.
      final turns = purpose == ConversationPurpose.reference
          ? AiConversation.turns(history)
          : const <AiTurn>[];
      debug?.log('generation_start', {
        'stage': 'social',
        'historyTurns': turns.length,
        'purpose': purpose?.name ?? 'interpreted_social',
      });
      final text = await runtime.converse(
        AiConversation(
          instructions:
              '${AiConversation.baseInstructions}\n'
              'Authoritative supported capabilities: ${ChatHelpCatalog.capabilities}\n'
              'Describe your abilities using only these capabilities. Never invent additional services. '
              'Reply only to the latest permitted interaction with the assistant. '
              'General knowledge and unrelated topics are outside your role. You are the assistant; '
              '"you" in a user message addresses you. Preserve who said or did what. '
              'Use the recent conversation for references, names and corrections. '
              'Do not inspect, invent or quote financial figures. No financial advice. '
              'Respond directly in natural language, not JSON or a description of the message. '
              '${purpose == ConversationPurpose.courtesy ? 'Give one short acknowledgement. Do not resume a previous topic, offer a new task or ask a question.' : ''}'
              '${purpose == ConversationPurpose.reference ? 'Resolve the explicit reference from the dialogue; do not answer a different earlier topic.' : ''}',
          user: message,
          history: turns,
          notes: purpose == ConversationPurpose.reference
              ? AiConversation.memoryNotes(history)
              : const [],
          response: true,
        ),
      );
      debug?.raw('social', text);
      final reply = checkedReply(
        text,
        onRejected: (reason) {
          onRejected?.call(reason);
          debug?.log('response_rejected', {
            'stage': 'social',
            'reason': reason,
          });
        },
      );
      if (reply != null) {
        debug?.log('response_accepted', {
          'stage': 'social',
          'chars': reply.length,
        });
      }
      return reply;
    } catch (error) {
      debug?.error('social', error);
      return null;
    }
  }

  static String? checkedReply(String raw, {void Function(String)? onRejected}) {
    // Custom/test backends may still return the old labelled response.
    if (raw.trimLeft().startsWith('{')) {
      return checked(raw, onRejected: onRejected);
    }
    return checked(
      jsonEncode({'kind': 'SOCIAL', 'reply': raw}),
      onRejected: onRejected,
    );
  }

  static String? checked(String raw, {void Function(String)? onRejected}) {
    String? reject(String reason) {
      onRejected?.call(reason);
      return null;
    }

    if (raw.length > 600) return reject('envelope_over_600_chars');
    try {
      final value = jsonDecode(raw.trim());
      if (value is! Map ||
          value.length != 2 ||
          value['kind'] != 'SOCIAL' ||
          value['reply'] is! String) {
        return reject('invalid_social_response_shape');
      }
      final text = (value['reply'] as String).trim();
      if (text.isEmpty) return reject('empty_reply');
      if (text.length > 240) return reject('reply_over_240_chars');
      final policy = ChatPolicy.responseReply(text);
      if (policy != null) {
        return reject(
          policy == ChatPolicy.adviceReply
              ? 'output_advice_policy'
              : 'output_safety_policy',
        );
      }
      if (AiGuardrails.numbers(text).isNotEmpty) {
        return reject('numeric_content_in_social_reply');
      }
      final blocked = RegExp(
        r'[{}₹$]|https?://|www\.|\b(spent|earned|credited|debited|checked|updated|deleted|saved|transferred|forecast|guarantee|promise)\b|\b(?:your (?:balance|budget|income|expenses?) (?:is|are|was)|you (?:have|owe|paid|received))\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (blocked != null) {
        return reject('blocked_social_content:${blocked[0]}');
      }
      return text;
    } on FormatException {
      return reject('invalid_json');
    }
  }
}
