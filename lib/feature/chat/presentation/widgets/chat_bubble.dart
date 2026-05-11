import 'package:flutter/material.dart';
import 'package:xocobaby13/feature/chat/presentation/widgets/chat_style.dart';

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isMe;

  const ChatBubble({super.key, required this.text, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 6),
      bottomRight: Radius.circular(isMe ? 6 : 16),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? ChatPalette.outgoingBubble : ChatPalette.incomingBubble,
          borderRadius: radius,
          border: isMe
              ? Border.all(color: ChatPalette.inputBorder)
              : Border.all(color: ChatPalette.incomingBubble),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isMe ? ChatPalette.outgoingText : ChatPalette.incomingText,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.28,
          ),
        ),
      ),
    );
  }
}
