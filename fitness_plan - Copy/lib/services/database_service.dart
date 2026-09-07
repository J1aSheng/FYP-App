import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Required for debugPrint
import '../models/user_model.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance; //

  /// Fetches the user's data from Firestore and converts it to a UserModel.[cite: 4]
  Future<UserModel?> getUserProfile(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get(); //[cite: 4]
      if (doc.exists) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>, uid); //[cite: 4]
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e"); //[cite: 4]
    }
    return null;
  }

  /// Saves the initial user profile during setup[cite: 4]
  Future<void> saveUserProfile(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap()); //[cite: 4]
  }

  /// ✅ NEW: Logs workout activity and increments burned calories[cite: 4]
  Future<void> logWorkoutActivity({
    required String uid,
    required int calories,
    required String workoutTitle,
  }) async {
    // Generate a document ID based on today's date (YYYY-MM-DD)[cite: 4]
    String todayId = DateTime.now().toString().split(' ')[0]; //[cite: 4]

    DocumentReference dailyLogRef = _db
        .collection('users')
        .doc(uid)
        .collection('daily_logs')
        .doc(todayId); //[cite: 4]

    try {
      await dailyLogRef.set({
        'activities': FieldValue.arrayUnion([{
          'activity_name': workoutTitle,
          'calories_burned': calories,
          'logged_at': Timestamp.now(), //[cite: 4]
        }]),
        // This keeps a separate running total for calories burned today[cite: 4]
        'total_burned': FieldValue.increment(calories), 
        'last_updated': Timestamp.now(), //[cite: 4]
      }, SetOptions(merge: true)); //[cite: 4]
      
      debugPrint("Workout logged: $workoutTitle, $calories cal");
    } catch (e) {
      debugPrint("Failed to log workout: $e"); //[cite: 4]
      throw Exception("Failed to sync workout: $e");
    }
  }

  /// Logs a meal and updates calories in a single transaction[cite: 4]
  Future<void> logMealWithSync(String uid, Map<String, dynamic> foodData, String imagePath) async {
    String todayId = DateTime.now().toString().split(' ')[0]; //[cite: 4]
    int mealCalories = foodData['calories'] ?? 0; //[cite: 4]

    DocumentReference dailyLogRef = _db
        .collection('users')
        .doc(uid)
        .collection('daily_logs')
        .doc(todayId); //[cite: 4]

    try {
      await dailyLogRef.set({
        'meals': FieldValue.arrayUnion([{
          'food_name': foodData['food_name'] ?? 'Unknown Dish', //[cite: 4]
          'calories': mealCalories, //[cite: 4]
          'image_path': imagePath, //[cite: 4]
          'portion': foodData['portion'] ?? '1 serving', //[cite: 4]
          'logged_at': Timestamp.now(), //[cite: 4]
        }]),
        'total_calories': FieldValue.increment(mealCalories), //[cite: 4]
        'last_updated': Timestamp.now(), //[cite: 4]
      }, SetOptions(merge: true)); //[cite: 4]
    } catch (e) {
      debugPrint("Failed to sync meal: $e"); //[cite: 4]
      throw Exception("Failed to sync meal: $e"); //[cite: 4]
    }
  }

  /// Retrieves the stream of logs for the current day[cite: 4]
  Stream<DocumentSnapshot> getDailyStream(String uid) {
    String todayId = DateTime.now().toString().split(' ')[0]; //[cite: 4]
    return _db.collection('users').doc(uid).collection('daily_logs').doc(todayId).snapshots(); //[cite: 4]
  }
}