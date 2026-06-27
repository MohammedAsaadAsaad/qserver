import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import '../models/chat_message.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'login_view.dart';
import 'widgets/sidebar.dart';
import 'widgets/chat_window.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiService _apiService = ApiService();
  final WebSocketService _webSocketService = WebSocketService();
  final DatabaseService _dbService = DatabaseService.instance;

  String? currentUser;
  String? activeContact;
  List<ChatMessage> chatHistory = [];
  Map<String, ChatMessage> lastMessages = {};

  final Set<String> _typingUsers = {};
  bool _localIsTyping = false;
  Timer? _typingTimer;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> contactsList = ['Alice', 'Bob', 'Charlie', 'Diana'];

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (currentUser == null || activeContact == null) return;
    final text = _messageController.text;
    if (text.isNotEmpty && !_localIsTyping) {
      _localIsTyping = true;
      _webSocketService.sendTypingState(currentUser!, activeContact!, true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_localIsTyping) {
        _localIsTyping = false;
        _webSocketService.sendTypingState(currentUser!, activeContact!, false);
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  LinearGradient getAvatarGradient(String name) {
    switch (name.toLowerCase()) {
      case 'alice':
        return const LinearGradient(colors: [Color(0xFFff9a9e), Color(0xFFfecfef)]);
      case 'bob':
        return const LinearGradient(colors: [Color(0xFFa1c4fd), Color(0xFFc2e9fb)]);
      case 'charlie':
        return const LinearGradient(colors: [Color(0xFFf6d365), Color(0xFFfda085)]);
      case 'diana':
        return const LinearGradient(colors: [Color(0xFFd4fc79), Color(0xFF96e6a1)]);
      default:
        return const LinearGradient(colors: [Color(0xFF00a884), Color(0xFF008069)]);
    }
  }

  Future<void> saveMessageToLocal(ChatMessage msg) async {
    try {
      await _dbService.saveMessage(msg);
    } catch (e) {
      debugPrint('Error saving message to local DB: $e');
    }
  }

  Future<void> loadChatHistoryFromLocal(String contact) async {
    if (currentUser == null) return;
    try {
      final messages = await _dbService.getChatHistory(currentUser!, contact);
      setState(() {
        chatHistory = messages;
      });
      scrollToBottom();
    } catch (e) {
      debugPrint('Error loading chat history from local DB: $e');
    }
  }

  Future<void> fetchLastMessageFromLocal(String contact) async {
    if (currentUser == null) return;
    try {
      final lastMsg = await _dbService.getLastMessage(currentUser!, contact);
      if (lastMsg != null) {
        setState(() {
          lastMessages[contact] = lastMsg;
        });
      }
    } catch (e) {
      debugPrint('Error loading last message from local DB: $e');
    }
  }

  void loginAs(String username) {
    setState(() {
      currentUser = username;
      activeContact = null;
      chatHistory.clear();
      lastMessages.clear();
      _typingUsers.clear();
      _localIsTyping = false;
    });

    for (var contact in contactsList) {
      if (contact != currentUser) {
        fetchLastMessage(contact);
      }
    }

    connectWebSocket();
  }

  void logout() {
    if (_localIsTyping && activeContact != null) {
      _webSocketService.sendTypingState(currentUser!, activeContact!, false);
    }
    _typingTimer?.cancel();
    _localIsTyping = false;
    _webSocketService.close();
    setState(() {
      currentUser = null;
      activeContact = null;
      chatHistory.clear();
      lastMessages.clear();
      _typingUsers.clear();
    });
  }

  void connectWebSocket() {
    if (currentUser == null) return;

    try {
      _webSocketService.connect(
        currentUser!,
        (data) {
          try {
            final payload = jsonDecode(data);
            if (payload['event'] == 'MessageReceived') {
              final msgJson = payload['data'];
              final message = ChatMessage.fromJson(msgJson);

              final otherUser = message.sender == currentUser ? message.receiver : message.sender;
              setState(() {
                lastMessages[otherUser] = message;
              });

              if (activeContact != null &&
                  ((message.sender == currentUser && message.receiver == activeContact) ||
                   (message.sender == activeContact && message.receiver == currentUser))) {
                setState(() {
                  chatHistory.add(message);
                });
                scrollToBottom();
              }

              saveMessageToLocal(message);
            } else if (payload['event'] == 'TypingStateChanged') {
              final eventData = payload['data'];
              final sender = eventData['sender'];
              final isTyping = eventData['isTyping'] ?? false;
              if (sender != null) {
                setState(() {
                  if (isTyping) {
                    _typingUsers.add(sender);
                  } else {
                    _typingUsers.remove(sender);
                  }
                });
              }
            }
          } catch (e) {
            debugPrint('Error parsing WebSocket message: $e');
          }
        },
        (err) {
          debugPrint('WebSocket error: $err. Reconnecting...');
          _showError('WebSocket connection error: $err');
          Future.delayed(const Duration(seconds: 3), connectWebSocket);
        },
        () {
          debugPrint('WebSocket disconnected. Reconnecting...');
          _showError('WebSocket disconnected. Reconnecting...');
          Future.delayed(const Duration(seconds: 3), connectWebSocket);
        },
      );
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _showError('WebSocket connection failed: $e');
    }
  }

  Future<void> loadChatHistory(String contact) async {
    if (currentUser == null) return;

    await loadChatHistoryFromLocal(contact);

    try {
      final fetchedMessages = await _apiService.fetchChatHistory(currentUser!, contact);
      for (var msg in fetchedMessages) {
        await saveMessageToLocal(msg);
      }
      await loadChatHistoryFromLocal(contact);
    } catch (e) {
      debugPrint('Failed to load chat history: $e');
      _showError('Failed to load chat history: $e');
    }
  }

  Future<void> fetchLastMessage(String contact) async {
    await fetchLastMessageFromLocal(contact);

    try {
      final lastMsg = await _apiService.fetchLastMessage(currentUser!, contact);
      if (lastMsg != null) {
        await saveMessageToLocal(lastMsg);
        await fetchLastMessageFromLocal(contact);
      }
    } catch (e) {
      debugPrint('Error fetching last message for $contact: $e');
      _showError('Error fetching last message for $contact: $e');
    }
  }

  Future<void> sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || activeContact == null || currentUser == null) return;

    _messageController.clear();

    try {
      await _apiService.sendMessage(currentUser!, activeContact!, text);
    } catch (e) {
      debugPrint('Error posting message: $e');
      _showError('Error posting message: $e');
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _typingTimer?.cancel();
    _webSocketService.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return LoginView(
        contactsList: contactsList,
        onLogin: loginAs,
        getAvatarGradient: getAvatarGradient,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFeae6df),
      body: Center(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 380,
                child: Sidebar(
                  currentUser: currentUser!,
                  activeContact: activeContact,
                  contactsList: contactsList,
                  lastMessages: lastMessages,
                  typingUsers: _typingUsers,
                  getAvatarGradient: getAvatarGradient,
                  onContactSelected: (contact) {
                    if (activeContact != contact) {
                      if (_localIsTyping && activeContact != null) {
                        _localIsTyping = false;
                        _webSocketService.sendTypingState(currentUser!, activeContact!, false);
                      }
                      _typingTimer?.cancel();
                      setState(() {
                        activeContact = contact;
                      });
                      loadChatHistory(contact);
                    }
                  },
                  onLogout: logout,
                  formatTime: formatTime,
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFe9edef)),
              Expanded(
                child: ChatWindow(
                  currentUser: currentUser!,
                  activeContact: activeContact,
                  chatHistory: chatHistory,
                  typingUsers: _typingUsers,
                  messageController: _messageController,
                  scrollController: _scrollController,
                  getAvatarGradient: getAvatarGradient,
                  onSendMessage: sendMessage,
                  formatTime: formatTime,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
