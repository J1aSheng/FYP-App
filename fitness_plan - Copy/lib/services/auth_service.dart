import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 处理用户登录
  Future<String?> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An error occurred during login.";
    } catch (e) {
      return "An unexpected error occurred.";
    }
  }

  // ✅ 新增：发送重置密码邮件功能，修复 undefined_method 报错[cite: 6]
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null; // 成功发送
    } on FirebaseAuthException catch (e) {
      return e.message ?? "Failed to send reset email.";
    } catch (e) {
      return "An unexpected error occurred.";
    }
  }

  // 处理用户注册并保存个人资料
  Future<String?> register(String email, String password, String name, {Map<String, dynamic>? extraData}) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      await credential.user?.updateDisplayName(name);

      Map<String, dynamic> userData = {
        'uid': credential.user?.uid,
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      }; 

      if (extraData != null) {
        userData.addAll(extraData);
      } 

      await _db.collection('users').doc(credential.user?.uid).set(userData);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An error occurred during registration.";
    } catch (e) {
      return "An unexpected error occurred.";
    }
  }

  // 登出功能
  Future<void> logout() async {
    await _auth.signOut();
  }
}