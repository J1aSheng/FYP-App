import 'package:flutter/material.dart';
import '../services/groq_ai_service.dart';
import '../models/user_model.dart';

class AiCoachScreen extends StatefulWidget {
  final UserModel user;
  const AiCoachScreen({super.key, required this.user});

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController(); // 用于自动滚动
  final List<Map<String, String>> _messages = [];
  final _ai = GroqAiService();
  bool _isTyping = false;

  // 建议问题列表，增加互动感
  final List<String> _suggestions = [
    "How to lose weight?",
    "Give me a 10-min workout",
    "Healthy meal ideas",
  ];

  // 自动滚动到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage({String? text}) async {
    String messageText = text ?? _controller.text.trim();
    if (messageText.isEmpty) return;

    setState(() {
      _messages.add({"role": "user", "text": messageText});
      _isTyping = true;
      if (text == null) _controller.clear();
    });
    _scrollToBottom();

    try {
      final prompt = "User Goal: ${widget.user.goal}. User Question: $messageText";
      final response = await _ai.getChatResponse(prompt);

      if (mounted) {
        setState(() {
          _messages.add({
            "role": "ai",
            "text": response ?? "Coach is currently offline. Please try again later!"
          });
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({"role": "ai", "text": "Coach is currently offline. Please try again later!"});
        });
        _scrollToBottom();
      }
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFA), 
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5, // 增加一点阴影
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text(
              "AI COACH", 
              style: TextStyle(color: Color(0xFF191C19), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2)
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 聊天內容區域
          Expanded(
            child: _messages.isEmpty ? _buildWelcomeState() : _buildChatList(),
          ),

          // 输入区域
          _buildInputArea(),
        ],
      ),
    );
  }

  // ✅ 新增：空状态欢迎界面
  Widget _buildWelcomeState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), shape: BoxShape.circle),
              child: const Icon(Icons.fitness_center_rounded, size: 60, color: Color(0xFF2E7D32)),
            ),
            const SizedBox(height: 20),
            Text("Hi, ${widget.user.name}!", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
              child: Text(
                "I am your personal AI coach. How can I help you reach your goals today?",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
            ),
            const SizedBox(height: 30),
            // 建议标签
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _suggestions.map((s) => ActionChip(
                label: Text(s),
                labelStyle: const TextStyle(color: Color(0xFF2E7D32), fontSize: 12),
                backgroundColor: Colors.white,
                shape: StadiumBorder(side: BorderSide(color: Colors.green.shade100)),
                onPressed: () => _sendMessage(text: s),
              )).toList(),
            )
          ],
        ),
      ),
    );
  }

  // ✅ 构建聊天列表
  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        bool isUser = _messages[index]["role"] == "user";
        return _buildMessageBubble(_messages[index]["text"]!, isUser);
      },
    );
  }

  // ✅ 增强：好看的消息气泡 (增加头像)
  Widget _buildMessageBubble(String text, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF2E7D32),
              child: Icon(Icons.smart_toy_outlined, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2E7D32) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: isUser ? null : Border.all(color: const Color(0xFFF0F0F0)),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF191C19),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFE8F5E9),
              child: Icon(Icons.person, size: 18, color: Color(0xFF2E7D32)),
            ),
          ],
        ],
      ),
    );
  }

  // ✅ 构建输入区域 (保持原色，增强细节)
  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -5)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                   SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32)),
                  ),
                  SizedBox(width: 10),
                  Text("Coach is thinking...", style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7F5),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TextField(
                    controller: _controller,
                    maxLines: null, // 允许换行
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: "Ask your coach something...",
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 发送按钮
              GestureDetector(
                onTap: () => _sendMessage(),
                child: Container(
                  height: 45, width: 45,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}