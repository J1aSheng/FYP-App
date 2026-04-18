import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class DatabaseService {
  final _db = FirebaseFirestore.instance;

  // Save/Get Profile
  Future<void> saveUserProfile(UserModel user) async => await _db.collection('users').doc(user.uid).set(user.toMap());
  
  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists ? UserModel.fromMap(doc.data()!, doc.id) : null;
  }

  // Log Meal with Auto-ID and Batch Sync
  Future<void> logMealWithSync(String uid, Map<String, dynamic> foodData, String localPath) async {
    final batch = _db.batch();
    final now = DateTime.now();
    final today = now.toString().split(' ')[0];

    // 1. Add to Meal Collection
    final mealRef = _db.collection('users').doc(uid).collection('meals').doc();
    batch.set(mealRef, {
      'name': foodData['name'] ?? 'Unknown',
      'calories': foodData['calories'] ?? 0,
      'imageUrl': localPath,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 2. Update Daily Aggregates (For your dashboard ring)
    final dailyRef = _db.collection('users').doc(uid).collection('daily_logs').doc(today);
    batch.set(dailyRef, {
      'total_calories': FieldValue.increment(foodData['calories'] ?? 0),
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Stream<List<MealPlan>> getTodaysMeals(String uid) {
    return _db.collection('users').doc(uid).collection('meals')
        .orderBy('timestamp', descending: true)
        .snapshots().map((s) => s.docs.map((d) => MealPlan(
          id: d.id,
          name: d['name'],
          calories: d['calories'],
          imageUrl: d['imageUrl'],
        )).toList());
  }

  Future<void> deleteMeal(String uid, String mealId) async {
    await _db.collection('users').doc(uid).collection('meals').doc(mealId).delete();
  }
}