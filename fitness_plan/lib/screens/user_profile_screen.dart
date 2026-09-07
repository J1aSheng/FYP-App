import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ 用于登出
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ 用于实时同步
import '../models/user_model.dart'; //
import 'edit_profile_screen.dart'; //[cite: 10]
import 'login_screen.dart'; // ✅ 登出后跳转回登录页

class ProfileScreen extends StatefulWidget {
  final UserModel user;

  const ProfileScreen({super.key, required this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color accentColor = Color(0xFF2E7D32); // 森林绿主题[cite: 5]

  @override
  Widget build(BuildContext context) {
    // ✅ 核心修复：使用 StreamBuilder 解决数据（如 age）不同步的问题[cite: 8]
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        // 数据加载中或文档不存在时的处理[cite: 8]
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: accentColor)),
          );
        }

        // ✅ 将最新的 Firebase 原始数据转为模型对象[cite: 1, 8]
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final currentUser = UserModel.fromMap(data, widget.user.uid);

        return Scaffold(
          backgroundColor: const Color(0xFFFBFDFA),
          appBar: AppBar(
            title: const Text(
              "PROFILE",
              style: TextStyle(
                  color: Color(0xFF191C19),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2),
            ),
            backgroundColor: Colors.white,
            elevation: 0.5,
            centerTitle: true,
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            children: [
              // --- 1. 动态个人资料头部 (包含 Edit 按钮) ---[cite: 5, 9]
              _buildProfileHeader(currentUser),

              // --- 2. 身体数据卡片 (Weight & Height) ---[cite: 5]
              _buildHealthMetricsSection(currentUser),

              // --- 3. 健身配置信息 (Age 就在这里同步) ---[cite: 1, 5]
              _buildSectionHeader("Fitness Profile"),
              // ✅ 数据库字段名为 currentStreak
              _buildInfoTile(Icons.local_fire_department_rounded, "Current Streak", "${currentUser.currentStreak} Days"),
              _buildInfoTile(Icons.flag_rounded, "Goal", currentUser.goal),
              _buildInfoTile(Icons.bar_chart_rounded, "Activity Level", currentUser.level),
              _buildInfoTile(Icons.cake_rounded, "Age", "${currentUser.age} years old"),
              _buildInfoTile(Icons.person_outline, "Gender", currentUser.gender),

              // --- 4. 其他偏好设置 ---[cite: 5]
              _buildSectionHeader("Preferences"),
              _buildActionTile(Icons.notifications_none_outlined, "Daily Reminders", () {}),
              _buildActionTile(Icons.privacy_tip_outlined, "Privacy Policy", () {}),

              // --- 5. 登出按钮 ---[cite: 5]
              const SizedBox(height: 30),
              _buildSignOutButton(),
              const SizedBox(height: 50),
            ],
          ),
        );
      },
    );
  }

  // ✅ 顶部头像与信息部分[cite: 5, 9]
  Widget _buildProfileHeader(UserModel user) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 45,
            backgroundColor: accentColor.withOpacity(0.1),
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : "U",
              style: const TextStyle(color: accentColor, fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 15),
          Text(user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text("📍 ${user.location}", style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: () {
              // 跳转到编辑页面并传入最新的 user 对象[cite: 10]
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => EditProfileScreen(user: user)),
              );
            },
            icon: const Icon(Icons.edit, size: 16),
            label: const Text("Edit Profile"),
            style: OutlinedButton.styleFrom(
              foregroundColor: accentColor,
              side: BorderSide(color: accentColor.withOpacity(0.3)),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 身体数据卡片展示[cite: 5]
  Widget _buildHealthMetricsSection(UserModel user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      child: Row(
        children: [
          _buildMetricCard("Weight", "${user.weight} kg", Icons.monitor_weight_outlined),
          const SizedBox(width: 15),
          _buildMetricCard("Height", "${user.height} cm", Icons.height_rounded),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
        ),
        child: Column(
          children: [
            Icon(icon, color: accentColor, size: 24),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return ListTile(
      leading: Icon(icon, color: accentColor, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      trailing: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
    );
  }

  Widget _buildActionTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: accentColor, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  // ✅ 功能点：Logout 逻辑实现[cite: 7]
  Widget _buildSignOutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextButton(
        onPressed: () async {
          // 弹出确认框
          bool? confirm = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Logout"),
              content: const Text("Are you sure you want to sign out?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                TextButton(
                  onPressed: () => Navigator.pop(context, true), 
                  child: const Text("Confirm", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
                ),
              ],
            ),
          );

          if (confirm == true) {
            // 1. Firebase 登出[cite: 7]
            await FirebaseAuth.instance.signOut();
            
            // 2. 跳转回登录页并清空路由
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          }
        },
        style: TextButton.styleFrom(
          foregroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Colors.redAccent),
          ),
        ),
        child: const Text("Sign Out", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}