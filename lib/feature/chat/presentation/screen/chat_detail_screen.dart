import 'dart:async';
import 'dart:io';

import 'package:app_pigeon/app_pigeon.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:xocobaby13/core/constants/api_endpoints.dart';
import 'package:xocobaby13/core/common/widget/loading/app_shimmer.dart';
import 'package:xocobaby13/feature/chat/model/chat_api_mapper.dart';
import 'package:xocobaby13/feature/chat/model/chat_message_model.dart';
import 'package:xocobaby13/feature/chat/model/chat_thread_model.dart';
import 'package:xocobaby13/feature/chat/presentation/widgets/chat_bubble.dart';
import 'package:xocobaby13/feature/chat/presentation/widgets/chat_dialogs.dart';
import 'package:xocobaby13/feature/chat/presentation/widgets/chat_input_bar.dart';
import 'package:xocobaby13/feature/chat/presentation/widgets/chat_style.dart';
import 'package:xocobaby13/core/common/widget/button/loading_buttons.dart';

enum _ChatMenuAction { report, block }

class ChatDetailScreen extends StatefulWidget {
  final ChatThreadModel thread;

  const ChatDetailScreen({super.key, required this.thread});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composerController = TextEditingController();
  List<ChatMessageModel> _messages = <ChatMessageModel>[];
  bool _isLoading = false;
  String? _loadError;
  String _currentUserId = '';
  String _otherUserId = '';
  bool _isBlocked = false;
  bool _isSending = false;
  String _currentUserAvatarUrl = '';
  bool _socketInitialized = false;
  StreamSubscription<dynamic>? _newMessageSub;
  StreamSubscription<dynamic>? _updateMessageSub;
  StreamSubscription<dynamic>? _deleteMessageSub;
  StreamSubscription<dynamic>? _connectSub;
  final ImagePicker _imagePicker = ImagePicker();
  final List<XFile> _pendingImages = <XFile>[];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    _newMessageSub?.cancel();
    _updateMessageSub?.cancel();
    _deleteMessageSub?.cancel();
    _scrollController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final String text = _composerController.text.trim();
    if (_isSending) {
      return;
    }
    if (text.isEmpty && _pendingImages.isEmpty) {
      return;
    }
    final List<XFile> pendingImages = _pendingImages.length > 5
        ? _pendingImages.take(5).toList()
        : List<XFile>.from(_pendingImages);
    final List<ChatMessageModel> optimisticMessages = _buildOptimisticMessages(
      text,
      pendingImages,
    );
    final List<String> optimisticIds = optimisticMessages
        .map((ChatMessageModel message) => message.id)
        .toList(growable: false);
    _composerController.clear();
    setState(() {
      _isSending = true;
      if (optimisticMessages.isNotEmpty) {
        _messages = _mergedMessages(_messages, optimisticMessages);
      }
      if (_pendingImages.isNotEmpty) {
        _pendingImages.clear();
      }
    });
    _scrollToBottom();
    try {
      final response = pendingImages.isNotEmpty
          ? await _sendMultipartMessage(text, pendingImages)
          : await Get.find<AuthorizedPigeon>().post(
              ApiEndpoints.sendMessage,
              data: <String, dynamic>{'chatId': widget.thread.id, 'text': text},
            );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      final List<ChatMessageModel> newMessages = data is List && data.isNotEmpty
          ? ChatApiMapper.messagesFromList(data, _currentUserId)
          : <ChatMessageModel>[];
      if (!mounted) return;
      _replaceOptimisticMessages(optimisticIds, newMessages);
    } catch (e) {
      if (mounted) {
        _removeMessagesById(optimisticIds);
        if (_composerController.text.trim().isEmpty && text.isNotEmpty) {
          _composerController.text = text;
          _composerController.selection = TextSelection.fromPosition(
            TextPosition(offset: _composerController.text.length),
          );
        }
        if (_pendingImages.isEmpty && pendingImages.isNotEmpty) {
          setState(() => _pendingImages.addAll(pendingImages));
        }
        _showMessage('Failed to send message');
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      _currentUserId = await _resolveCurrentUserId();
      await _initSocketIfNeeded();
      final response = await Get.find<AuthorizedPigeon>().get(
        ApiEndpoints.getSingleChat(widget.thread.id),
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      final Map<String, dynamic> chat = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      final List<ChatMessageModel> messages = ChatApiMapper.messagesFromChat(
        chat,
        _currentUserId,
      );
      final String otherUserId = widget.thread.otherUserId.isNotEmpty
          ? widget.thread.otherUserId
          : ChatApiMapper.otherUserIdFromChat(chat, _currentUserId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _otherUserId = otherUserId;
        _isLoading = false;
      });
      await _loadBlockedStatus(otherUserId);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load messages';
        _isLoading = false;
      });
    }
  }

  Future<String> _resolveCurrentUserId() async {
    try {
      final authRecord = await Get.find<AuthorizedPigeon>()
          .getCurrentAuthRecord();
      final Map<String, dynamic> data = authRecord?.data is Map
          ? Map<String, dynamic>.from(authRecord!.data as Map)
          : <String, dynamic>{};
      final dynamic raw = authRecord?.toJson();
      final Map<String, dynamic> record = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      return _pickFirstString(<dynamic>[
        data['id'],
        data['_id'],
        data['userId'],
        record['uid'],
        record['userId'],
        record['user_id'],
        record['id'],
        record['_id'],
      ]);
    } catch (_) {
      return '';
    }
  }

  String _pickFirstString(List<dynamic> values) {
    for (final dynamic value in values) {
      final String text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  Future<void> _initSocketIfNeeded() async {
    if (_socketInitialized || _currentUserId.isEmpty) {
      return;
    }
    final pigeon = Get.find<AuthorizedPigeon>();
    await pigeon.socketInit(
      SocketConnetParamX(
        token: null,
        socketUrl: ApiEndpoints.socketUrl,
        joinId: _currentUserId,
      ),
    );
    _connectSub = pigeon.listen('connect').listen((_) {
      pigeon.emit('joinChatRoom', _currentUserId);
    });
    pigeon.emit('joinChatRoom', _currentUserId);
    _newMessageSub = pigeon.listen('newMessage').listen(_handleNewMessageEvent);
    _updateMessageSub = pigeon
        .listen('messageUpdated')
        .listen(_handleMessageUpdatedEvent);
    _deleteMessageSub = pigeon
        .listen('messageDeleted')
        .listen(_handleMessageDeletedEvent);
    _socketInitialized = true;
  }

  void _handleNewMessageEvent(dynamic payload) {
    final Map<String, dynamic> data = _asMap(payload);
    final String chatId = data['chatId']?.toString() ?? '';
    if (chatId != widget.thread.id) {
      return;
    }
    final dynamic messageRaw = data['message'];
    if (messageRaw is! Map) {
      return;
    }
    final ChatMessageModel message = ChatApiMapper.messageFromMap(
      Map<String, dynamic>.from(messageRaw),
      _currentUserId,
    );
    if (!mounted) return;
    if (message.isMe && _replaceMatchingOptimisticMessage(message)) {
      return;
    }
    final bool alreadyVisible = _messages.any(
      (ChatMessageModel item) => item.id == message.id,
    );
    _mergeMessages(<ChatMessageModel>[message]);
    if (!alreadyVisible && !message.isMe) {
      _scrollToBottom();
    }
  }

  void _handleMessageUpdatedEvent(dynamic payload) {
    final Map<String, dynamic> data = _asMap(payload);
    final String chatId = data['chatId']?.toString() ?? '';
    if (chatId != widget.thread.id) {
      return;
    }
    final dynamic messageRaw = data['message'];
    if (messageRaw is! Map) {
      return;
    }
    final ChatMessageModel message = ChatApiMapper.messageFromMap(
      Map<String, dynamic>.from(messageRaw),
      _currentUserId,
    );
    if (!mounted) return;
    _mergeMessages(<ChatMessageModel>[message]);
  }

  void _handleMessageDeletedEvent(dynamic payload) {
    final Map<String, dynamic> data = _asMap(payload);
    final String chatId = data['chatId']?.toString() ?? '';
    if (chatId != widget.thread.id) {
      return;
    }
    final String messageId = data['messageId']?.toString() ?? '';
    if (messageId.isEmpty) return;
    if (!mounted) return;
    _removeMessage(messageId);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  List<ChatMessageModel> _buildOptimisticMessages(
    String text,
    List<XFile> pendingImages,
  ) {
    final DateTime now = DateTime.now();
    final List<ChatMessageModel> messages = <ChatMessageModel>[];
    if (text.isNotEmpty) {
      messages.add(
        ChatMessageModel(
          id: 'local-text-${now.microsecondsSinceEpoch}',
          text: text,
          isMe: true,
          timestamp: now,
        ),
      );
    }
    for (int index = 0; index < pendingImages.length; index++) {
      final XFile file = pendingImages[index];
      messages.add(
        ChatMessageModel(
          id: 'local-image-${now.microsecondsSinceEpoch}-$index',
          text: text.isEmpty ? 'Photo' : text,
          isMe: true,
          timestamp: now.add(Duration(milliseconds: index + 1)),
          type: 'image',
          localPath: file.path,
        ),
      );
    }
    return messages;
  }

  void _mergeMessages(List<ChatMessageModel> incoming) {
    if (incoming.isEmpty) return;
    setState(() => _messages = _mergedMessages(_messages, incoming));
  }

  List<ChatMessageModel> _mergedMessages(
    List<ChatMessageModel> current,
    List<ChatMessageModel> incoming,
  ) {
    if (incoming.isEmpty) {
      return current;
    }
    final Map<String, ChatMessageModel> byId = <String, ChatMessageModel>{
      for (final ChatMessageModel message in current) message.id: message,
    };
    for (final ChatMessageModel message in incoming) {
      byId[message.id] = message;
    }
    final List<ChatMessageModel> updated = byId.values.toList();
    updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return updated;
  }

  void _removeMessage(String messageId) {
    final List<ChatMessageModel> updated = _messages
        .where((m) => m.id != messageId)
        .toList();
    if (updated.length == _messages.length) return;
    setState(() => _messages = updated);
  }

  void _removeMessagesById(List<String> messageIds) {
    if (messageIds.isEmpty) return;
    final Set<String> ids = messageIds.toSet();
    final List<ChatMessageModel> updated = _messages
        .where((ChatMessageModel message) => !ids.contains(message.id))
        .toList();
    if (updated.length == _messages.length) return;
    setState(() => _messages = updated);
  }

  void _replaceOptimisticMessages(
    List<String> optimisticIds,
    List<ChatMessageModel> newMessages,
  ) {
    final Set<String> ids = optimisticIds.toSet();
    final List<ChatMessageModel> updated = List<ChatMessageModel>.from(
      _messages,
    );
    int replacementIndex = 0;
    for (int index = 0; index < updated.length; index++) {
      if (!ids.contains(updated[index].id)) {
        continue;
      }
      if (replacementIndex < newMessages.length) {
        updated[index] = newMessages[replacementIndex];
        replacementIndex++;
      } else {
        updated.removeAt(index);
        index--;
      }
    }
    while (replacementIndex < newMessages.length) {
      updated.add(newMessages[replacementIndex]);
      replacementIndex++;
    }
    if (newMessages.isEmpty) {
      if (updated.length != _messages.length) {
        setState(() => _messages = updated);
      }
      return;
    }
    setState(() => _messages = _dedupeSortedMessages(updated));
  }

  bool _replaceMatchingOptimisticMessage(ChatMessageModel serverMessage) {
    final int index = _messages.indexWhere((ChatMessageModel message) {
      return message.isMe &&
          message.id.startsWith('local-') &&
          message.type == serverMessage.type &&
          message.text == serverMessage.text;
    });
    if (index == -1) {
      return false;
    }
    final List<ChatMessageModel> updated = List<ChatMessageModel>.from(
      _messages,
    );
    updated[index] = serverMessage;
    setState(() => _messages = _dedupeSortedMessages(updated));
    return true;
  }

  List<ChatMessageModel> _dedupeSortedMessages(
    List<ChatMessageModel> messages,
  ) {
    final Map<String, ChatMessageModel> byId = <String, ChatMessageModel>{
      for (final ChatMessageModel message in messages) message.id: message,
    };
    final List<ChatMessageModel> updated = byId.values.toList();
    updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return updated;
  }

  Future<void> _loadBlockedStatus(String otherUserId) async {
    if (otherUserId.isEmpty) return;
    try {
      final response = await Get.find<AuthorizedPigeon>().get(
        ApiEndpoints.getCurrentProfile,
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      if (data is Map) {
        final String avatarUrl = data['avatar'] is Map
            ? data['avatar']['url']?.toString() ?? ''
            : '';
        final blockedUsers = data['blockedUsers'];
        if (blockedUsers is List) {
          final bool isBlocked = blockedUsers.any(
            (dynamic id) => id?.toString() == otherUserId,
          );
          if (mounted) {
            setState(() => _isBlocked = isBlocked);
          }
        }
        if (mounted && avatarUrl.isNotEmpty) {
          setState(() => _currentUserAvatarUrl = avatarUrl);
        }
      }
    } catch (_) {
      // Ignore block status load errors.
    }
  }

  Future<bool> _createReport(String reason) async {
    if (_otherUserId.isEmpty) {
      _showMessage('Unable to report this user');
      return false;
    }
    try {
      await Get.find<AuthorizedPigeon>().post(
        ApiEndpoints.sendReport,
        data: <String, dynamic>{
          'reportedUser': _otherUserId,
          'reason': reason,
          'chatId': widget.thread.id,
        },
      );
      return true;
    } catch (_) {
      _showMessage('Failed to submit report');
      return false;
    }
  }

  Future<bool?> _toggleBlockStatus() async {
    if (_otherUserId.isEmpty) {
      _showMessage('Unable to update block status');
      return null;
    }
    try {
      if (_isBlocked) {
        await Get.find<AuthorizedPigeon>().patch(
          ApiEndpoints.unblockUser(_otherUserId),
        );
        if (mounted) {
          setState(() => _isBlocked = false);
        }
        return false;
      }
      await Get.find<AuthorizedPigeon>().patch(
        ApiEndpoints.blockUser(_otherUserId),
      );
      if (mounted) {
        setState(() => _isBlocked = true);
      }
      return true;
    } catch (_) {
      _showMessage('Failed to update block status');
      return null;
    }
  }

  Future<void> _showMessageActions(ChatMessageModel message) async {
    final bool canEdit = message.isMe && message.type == 'text';
    final String? action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (canEdit)
                ListTile(
                  title: const Text(
                    'Edit message',
                    style: TextStyle(
                      color: ChatPalette.titleText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
              ListTile(
                title: const Text(
                  'Delete message',
                  style: TextStyle(
                    color: ChatPalette.dangerRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        );
      },
    );
    if (action == 'edit') {
      await _showEditMessageDialog(message);
    } else if (action == 'delete') {
      await _deleteMessage(message);
    }
  }

  Future<void> _showEditMessageDialog(ChatMessageModel message) async {
    final TextEditingController controller = TextEditingController(
      text: message.text,
    );
    final String? updatedText = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Edit message'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: <Widget>[
            AppTextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            AppTextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (updatedText == null || updatedText.trim().isEmpty) {
      return;
    }
    await _updateMessage(message, updatedText.trim());
  }

  Future<void> _updateMessage(ChatMessageModel message, String newText) async {
    try {
      final response = await Get.find<AuthorizedPigeon>().patch(
        ApiEndpoints.updateMessage,
        data: <String, dynamic>{
          'chatId': widget.thread.id,
          'messageId': message.id,
          'newText': newText,
        },
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      if (data is Map) {
        final ChatMessageModel updated = ChatApiMapper.messageFromMap(
          Map<String, dynamic>.from(data),
          _currentUserId,
        );
        if (!mounted) return;
        _mergeMessages(<ChatMessageModel>[updated]);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Failed to update message');
      }
    }
  }

  Future<void> _deleteMessage(ChatMessageModel message) async {
    try {
      await Get.find<AuthorizedPigeon>().delete(
        ApiEndpoints.deleteMessage,
        data: <String, dynamic>{
          'chatId': widget.thread.id,
          'messageId': message.id,
        },
      );
      if (!mounted) return;
      _removeMessage(message.id);
    } catch (_) {
      if (mounted) {
        _showMessage('Failed to delete message');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> selected = await _imagePicker.pickMultiImage();
      if (selected.isEmpty) return;
      final Set<String> existingPaths = _pendingImages
          .map((e) => e.path)
          .toSet();
      final List<XFile> uniqueNew = <XFile>[];
      for (final XFile file in selected) {
        if (existingPaths.add(file.path)) {
          uniqueNew.add(file);
        }
      }
      if (uniqueNew.isEmpty) {
        _showMessage('Image already selected');
        return;
      }
      setState(() {
        _pendingImages.addAll(uniqueNew);
        if (_pendingImages.length > 5) {
          _pendingImages.removeRange(5, _pendingImages.length);
        }
      });
      if (_pendingImages.length >= 5) {
        _showMessage('Only 5 images can be selected');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Failed to pick image');
      }
    }
  }

  void _removePendingImage(int index) {
    if (index < 0 || index >= _pendingImages.length) return;
    setState(() {
      _pendingImages.removeAt(index);
    });
  }

  Future<dio.Response<dynamic>> _sendMultipartMessage(
    String text,
    List<XFile> pendingImages,
  ) async {
    final List<XFile> filesToSend = pendingImages.length > 5
        ? pendingImages.take(5).toList()
        : List<XFile>.from(pendingImages);
    if (pendingImages.length > 5) {
      _showMessage('Only 5 images can be sent at a time');
    }
    final List<dio.MultipartFile> files = <dio.MultipartFile>[];
    for (final XFile file in filesToSend) {
      files.add(
        await dio.MultipartFile.fromFile(file.path, filename: file.name),
      );
    }
    final formData = dio.FormData.fromMap(<String, dynamic>{
      'chatId': widget.thread.id,
      'text': text,
      'files': files,
    });
    return Get.find<AuthorizedPigeon>().post(
      ApiEndpoints.sendMessage,
      data: formData,
      options: dio.Options(contentType: 'multipart/form-data'),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleMenuAction(_ChatMenuAction action) async {
    switch (action) {
      case _ChatMenuAction.report:
        await ChatDialogs.showReportReasonSheet(
          context: context,
          onReasonSelected: (String reason) async {
            await ChatDialogs.showReportDoneDialog(
              context: context,
              onReportSpotOwner: () async {
                final bool didReport = await _createReport(reason);
                if (!mounted) return;
                if (didReport) {
                  await ChatDialogs.showReportCompletedDialog(context: context);
                }
              },
            );
          },
        );
        return;
      case _ChatMenuAction.block:
        final bool? confirmed = await ChatDialogs.showBlockConfirmDialog(
          context: context,
        );
        if (confirmed == true && mounted) {
          final bool? blocked = await _toggleBlockStatus();
          if (!mounted || blocked == null) {
            return;
          }
          if (blocked) {
            await ChatDialogs.showBlockDoneDialog(context: context);
          } else {
            _showMessage('User unblocked');
          }
        }
        return;
    }
  }

  Widget _buildMessageRow(ChatMessageModel message) {
    if (message.isMe) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Flexible(
            child: GestureDetector(
              onLongPress: message.type == 'text'
                  ? () => _showMessageActions(message)
                  : null,
              child: _buildMessageContent(message),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: ChatPalette.statusDot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 8,
            backgroundColor: ChatPalette.actionBlue,
            backgroundImage: _currentUserAvatarUrl.isNotEmpty
                ? NetworkImage(_currentUserAvatarUrl)
                : null,
            child: _currentUserAvatarUrl.isEmpty
                ? const Text(
                    'ME',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 6,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  )
                : null,
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        CircleAvatar(
          radius: 8,
          backgroundColor: widget.thread.avatarColor,
          backgroundImage: widget.thread.avatarUrl.isNotEmpty
              ? NetworkImage(widget.thread.avatarUrl)
              : widget.thread.avatarAssetPath.isNotEmpty
              ? AssetImage(widget.thread.avatarAssetPath)
              : null,
          child:
              widget.thread.avatarUrl.isEmpty &&
                  widget.thread.avatarAssetPath.isEmpty
              ? Text(
                  widget.thread.avatarLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Flexible(child: _buildMessageContent(message)),
      ],
    );
  }

  Widget _buildMessageContent(ChatMessageModel message) {
    final bool isImage =
        message.type == 'image' &&
        ((message.mediaUrl ?? '').isNotEmpty ||
            (message.localPath ?? '').isNotEmpty);
    if (!isImage) {
      return ChatBubble(text: message.text, isMe: message.isMe);
    }

    final BorderRadius radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(message.isMe ? 16 : 6),
      bottomRight: Radius.circular(message.isMe ? 6 : 16),
    );

    return Container(
      constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: ChatPalette.inputBorder),
        color: message.isMe ? ChatPalette.outgoingBubble : Colors.white,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: message.localPath != null && message.localPath!.isNotEmpty
            ? Image.file(
                File(message.localPath!),
                width: 220,
                height: 180,
                fit: BoxFit.cover,
              )
            : Image.network(
                message.mediaUrl ?? '',
                width: 220,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 220,
                  height: 180,
                  color: ChatPalette.outgoingBubble,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    size: 28,
                    color: ChatPalette.subtitleText,
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChatPalette.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(
                children: <Widget>[
                  AppIconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 20,
                      color: ChatPalette.titleText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: widget.thread.avatarColor,
                    backgroundImage: widget.thread.avatarUrl.isNotEmpty
                        ? NetworkImage(widget.thread.avatarUrl)
                        : widget.thread.avatarAssetPath.isNotEmpty
                        ? AssetImage(widget.thread.avatarAssetPath)
                        : null,
                    child:
                        widget.thread.avatarUrl.isEmpty &&
                            widget.thread.avatarAssetPath.isEmpty
                        ? Text(
                            widget.thread.avatarLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.thread.name,
                          style: const TextStyle(
                            color: ChatPalette.titleText,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.thread.subtitle,
                          style: const TextStyle(
                            color: ChatPalette.subtitleText,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_ChatMenuAction>(
                    onSelected: _handleMenuAction,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    offset: const Offset(0, 36),
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<_ChatMenuAction>>[
                          const PopupMenuItem<_ChatMenuAction>(
                            height: 32,
                            value: _ChatMenuAction.report,
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.flag_outlined, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Report',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem<_ChatMenuAction>(
                            height: 32,
                            value: _ChatMenuAction.block,
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.block, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Block',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                    icon: const Icon(
                      Icons.more_vert,
                      color: ChatPalette.titleText,
                      size: 24,
                      weight: 100,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: ChatPalette.divider),
            Expanded(
              child: _isLoading
                  ? const _ChatConversationSkeleton()
                  : _loadError != null
                  ? Center(
                      child: Text(
                        _loadError ?? 'Failed to load messages',
                        style: const TextStyle(
                          color: ChatPalette.subtitleText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(
                          color: ChatPalette.subtitleText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      itemCount: _messages.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ChatMessageModel message = _messages[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildMessageRow(message),
                        );
                      },
                    ),
            ),
            ChatInputBar(
              controller: _composerController,
              onSend: _sendMessage,
              onAttach: _pickImages,
              attachmentPaths: _pendingImages
                  .map((XFile file) => file.path)
                  .toList(),
              onRemoveAttachment: _removePendingImage,
              isSending: _isSending,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatConversationSkeleton extends StatelessWidget {
  const _ChatConversationSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      children: const <Widget>[
        _ChatBubbleSkeleton(isMe: false, width: 170),
        SizedBox(height: 12),
        _ChatBubbleSkeleton(isMe: true, width: 130),
        SizedBox(height: 12),
        _ChatBubbleSkeleton(isMe: false, width: 210),
        SizedBox(height: 12),
        _ChatBubbleSkeleton(isMe: true, width: 160),
        SizedBox(height: 12),
        _ChatBubbleSkeleton(isMe: false, width: 145),
      ],
    );
  }
}

class _ChatBubbleSkeleton extends StatelessWidget {
  const _ChatBubbleSkeleton({required this.isMe, required this.width});

  final bool isMe;
  final double width;

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
      child: AppShimmer(
        child: Container(
          width: width,
          height: 40,
          decoration: BoxDecoration(
            color: isMe ? ChatPalette.outgoingBubble : const Color(0xFF5CB4EA),
            borderRadius: radius,
          ),
        ),
      ),
    );
  }
}
