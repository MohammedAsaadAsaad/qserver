import 'package:flutter/material.dart';
import '../../models/chat_message.dart';

class Sidebar extends StatelessWidget {
  final String currentUser;
  final String? activeContact;
  final List<String> contactsList;
  final Map<String, ChatMessage> lastMessages;
  final Set<String> typingUsers;
  final LinearGradient Function(String) getAvatarGradient;
  final Function(String) onContactSelected;
  final VoidCallback onLogout;
  final String Function(DateTime) formatTime;

  const Sidebar({
    super.key,
    required this.currentUser,
    required this.activeContact,
    required this.contactsList,
    required this.lastMessages,
    required this.typingUsers,
    required this.getAvatarGradient,
    required this.onContactSelected,
    required this.onLogout,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final otherContacts = contactsList.where((c) => c != currentUser).toList();

    return Column(
      children: [
        // Sidebar Header
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
                      gradient: getAvatarGradient(currentUser),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      currentUser[0],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    currentUser,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat_bubble, color: Color(0xFF667781)),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Color(0xFF667781)),
                    tooltip: 'Logout',
                    onPressed: onLogout,
                  ),
                ],
              )
            ],
          ),
        ),
        // Search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.white,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFf0f2f5),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Row(
              children: [
                Icon(Icons.search, size: 18, color: Color(0xFF667781)),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search or start new chat',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Contacts List
        Expanded(
          child: ListView.builder(
            itemCount: otherContacts.length,
            itemBuilder: (context, index) {
              final contact = otherContacts[index];
              final isSelected = activeContact == contact;
              final lastMsg = lastMessages[contact];
              final isTyping = typingUsers.contains(contact);
              final previewText = isTyping
                  ? 'typing...'
                  : (lastMsg != null
                      ? (lastMsg.sender == currentUser ? 'You: ${lastMsg.content}' : lastMsg.content)
                      : 'No messages yet');
              final previewTime = lastMsg != null ? formatTime(lastMsg.timestamp) : '';

              return InkWell(
                onTap: () => onContactSelected(contact),
                child: Container(
                  color: isSelected ? const Color(0xFFf0f2f5) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: getAvatarGradient(contact),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          contact[0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  contact,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  previewTime,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF667781),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              previewText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isTyping ? const Color(0xFF00a884) : const Color(0xFF667781),
                                fontWeight: isTyping ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
