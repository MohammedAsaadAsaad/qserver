import 'package:flutter/material.dart';
import '../../models/chat_message.dart';

class ChatWindow extends StatelessWidget {
  final String currentUser;
  final String? activeContact;
  final List<ChatMessage> chatHistory;
  final Set<String> typingUsers;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final LinearGradient Function(String) getAvatarGradient;
  final VoidCallback onSendMessage;
  final String Function(DateTime) formatTime;

  const ChatWindow({
    super.key,
    required this.currentUser,
    required this.activeContact,
    required this.chatHistory,
    required this.typingUsers,
    required this.messageController,
    required this.scrollController,
    required this.getAvatarGradient,
    required this.onSendMessage,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    if (activeContact == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFf0f2f5),
              ),
              child: const Icon(Icons.comments_disabled, size: 80, color: Color(0xFFcbd5e1)),
            ),
            const SizedBox(height: 20),
            const Text(
              'Select a contact to chat',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Real-time messaging demo showcasing Quds Server\'s WebSockets and SQLite integration.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748b), fontSize: 14),
            ),
          ],
        ),
      );
    }

    final isTyping = typingUsers.contains(activeContact);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFefeae2),
        image: DecorationImage(
          image: NetworkImage('https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png'),
          fit: BoxFit.cover,
          opacity: 0.06,
        ),
      ),
      child: Column(
        children: [
          // Active Contact Header
          Container(
            color: const Color(0xFFf0f2f5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: getAvatarGradient(activeContact!),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        activeContact![0],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeContact!,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        Text(
                          isTyping ? 'typing...' : 'online',
                          style: TextStyle(
                            fontSize: 11,
                            color: isTyping
                                ? const Color(0xFF00a884)
                                : const Color(0xFF667781),
                            fontWeight: isTyping
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Row(
                  children: [
                    Icon(Icons.videocam, color: Color(0xFF667781)),
                    SizedBox(width: 24),
                    Icon(Icons.phone, color: Color(0xFF667781)),
                    SizedBox(width: 24),
                    Icon(Icons.search, color: Color(0xFF667781)),
                  ],
                )
              ],
            ),
          ),
          // Messages List
          Expanded(
            child: chatHistory.isEmpty
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock, size: 12, color: Color(0xFF8696a0)),
                          SizedBox(width: 8),
                          Text(
                            'Messages are stored in local SQLite database.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF667781)),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    itemCount: chatHistory.length,
                    itemBuilder: (context, index) {
                      final msg = chatHistory[index];
                      final isOutgoing = msg.sender == currentUser;

                      return Align(
                        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 20),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.6,
                          ),
                          decoration: BoxDecoration(
                            color: isOutgoing ? const Color(0xFFd9fdd3) : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(8),
                              topRight: const Radius.circular(8),
                              bottomLeft: isOutgoing ? const Radius.circular(8) : Radius.zero,
                              bottomRight: isOutgoing ? Radius.zero : const Radius.circular(8),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 1,
                                offset: Offset(0, 1),
                              )
                            ],
                          ),
                          child: Stack(
                            children: [
                              Text(
                                msg.content,
                                style: const TextStyle(fontSize: 14.5, height: 1.4),
                              ),
                              Positioned(
                                bottom: -16,
                                right: 0,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      formatTime(msg.timestamp),
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF667781)),
                                    ),
                                    if (isOutgoing) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.done_all, size: 14, color: Color(0xFF53bdeb)),
                                    ]
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Input Panel
          Container(
            color: const Color(0xFFf0f2f5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.insert_emoticon, size: 24, color: Color(0xFF667781)),
                const SizedBox(width: 15),
                const Icon(Icons.attach_file, size: 24, color: Color(0xFF667781)),
                const SizedBox(width: 15),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: messageController,
                      onSubmitted: (_) => onSendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                InkWell(
                  onTap: onSendMessage,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF00a884),
                    ),
                    child: const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
