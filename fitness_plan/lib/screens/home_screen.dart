import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';
import '../services/gemini_ai_service.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ai = GeminiAiService();
  final _db = DatabaseService();
  final _picker = ImagePicker();
  
  List<Exercise> todayWorkouts = [];
  bool isLoadingWorkout = true;
  bool isScanning = false; 
  late double dailyTarget;

  @override
  void initState() {
    super.initState();
    dailyTarget = _calculateBMR();
    _fetchAiWorkout();
  }

  /// Calculates Daily Calorie Target based on the Mifflin-St Jeor Equation
  double _calculateBMR() {
    double bmr = widget.user.gender.toLowerCase() == "male" 
      ? 10 * widget.user.weight + 6.25 * widget.user.height - 5 * widget.user.age + 5
      : 10 * widget.user.weight + 6.25 * widget.user.height - 5 * widget.user.age - 161;
    
    if (widget.user.goal.contains("Lose")) {
      return bmr - 500;
    }
    if (widget.user.goal.contains("Muscle")) {
      return bmr + 300;
    }
    return bmr;
  }

  Future<void> _fetchAiWorkout() async {
    final list = await _ai.generateDailyWorkout(widget.user);
    if (mounted) {
      setState(() { 
        todayWorkouts = list; 
        isLoadingWorkout = false; 
      });
    }
  }

  Future<void> _scanFood() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera, 
      maxWidth: 1024, 
      imageQuality: 70
    );

    if (photo != null) {
      setState(() => isScanning = true);
      try {
        final foodData = await _ai.analyzeFoodImage(File(photo.path));
        
        if (foodData != null) {
          await _db.logMealWithSync(
            widget.user.uid, 
            foodData, 
            photo.path
          );
        } else {
          _showSnack("AI couldn't identify the food. Try again!");
        }
      } catch (e) {
        debugPrint("Scan Logic Error: $e");
      } finally {
        if (mounted) {
          setState(() => isScanning = false);
        }
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showImagePreview(MealPlan meal) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: _displayImage(meal.imageUrl, height: 300, width: double.infinity),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(meal.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text("${meal.calories} kcal", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 15),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00695C)),
                    child: const Text("Close", style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _displayImage(String path, {double? height, double? width}) {
    if (path.startsWith('http')) {
      return Image.network(path, height: height, width: width, fit: BoxFit.cover);
    } else {
      return Image.file(File(path), height: height, width: width, fit: BoxFit.cover);
    }
  }

  Future<bool?> _confirmDeletion(BuildContext context, String mealName) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Record?"),
        content: Text("Do you want to delete '$mealName'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Delete", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      bottomNavigationBar: _buildBottomNav(), 
      body: SafeArea(
        child: StreamBuilder<List<MealPlan>>(
          stream: _db.getTodaysMeals(widget.user.uid),
          builder: (context, snapshot) {
            final meals = snapshot.data ?? [];
            int total = meals.fold(0, (sum, m) => sum + m.calories);

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  _buildMainBanner(total),
                  const SizedBox(height: 15),
                  // FIXED: Removed curly braces to avoid "Set<Padding>" error
                  if (isScanning)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(color: Color(0xFF00695C)),
                    ),
                  const SizedBox(height: 10),
                  _buildSectionHeader("Consistency", "7 Day Streak"),
                  _buildStreakRow(),
                  const SizedBox(height: 25),
                  _buildSectionHeader("Today's Diet", "$total kcal"), 
                  // FIXED: Formatting collection-if and collection-for
                  if (meals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text("No meals logged yet today.", style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ...meals.map((m) => _buildMealCard(m)),
                  const SizedBox(height: 25),
                  _buildSectionHeader("AI Activity Plan", "SMART"),
                  _buildAiList(),
                  const SizedBox(height: 100),
                ],
              ),
            );
          }
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isScanning ? null : _scanFood, 
        label: Text(isScanning ? "Analyzing..." : "Scan Meal"),
        icon: const Icon(Icons.camera_alt),
        backgroundColor: const Color(0xFF1B5E20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.teal[100], 
            child: Text(
              widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : "U", 
              style: const TextStyle(color: Color(0xFF00695C), fontWeight: FontWeight.bold)
            )
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              Text("Hello, ${widget.user.name}!", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Text("Ready for your fitness goals?", style: TextStyle(color: Colors.grey, fontSize: 14)),
            ]
          ),
        ],
      ),
    );
  }

  Widget _buildMainBanner(int current) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF00695C), Color(0xFF2E7D32)]),
        borderRadius: BorderRadius.circular(25)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          const Text("Calories Consumed", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 5),
          Text("$current / ${dailyTarget.toInt()} kcal", 
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(10), 
            child: LinearProgressIndicator(
              value: dailyTarget > 0 ? (current / dailyTarget) : 0, 
              minHeight: 10, 
              // FIXED: Changed withOpacity to withValues
              backgroundColor: Colors.white.withValues(alpha: 0.2), 
              color: Colors.orangeAccent
            )
          ),
        ]
      ),
    );
  }

  Widget _buildSectionHeader(String t, String s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
      children: [
        Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
        Text(s, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500))
      ]
    );
  }

  Widget _buildStreakRow() {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
        children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) => Column(
          children: [
            Text(d, style: const TextStyle(fontSize: 12, color: Colors.grey)), 
            const SizedBox(height: 8), 
            Icon(Icons.check_circle, color: Colors.teal[50], size: 28)
          ]
        )).toList()
      ),
    );
  }

  Widget _buildMealCard(MealPlan m) {
    return Dismissible(
      key: Key(m.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) => _confirmDeletion(context, m.name),
      background: Container(
        margin: const EdgeInsets.only(top: 10), 
        decoration: BoxDecoration(color: Colors.red[400], borderRadius: BorderRadius.circular(20)), 
        alignment: Alignment.centerRight, 
        padding: const EdgeInsets.only(right: 20), 
        child: const Icon(Icons.delete_outline, color: Colors.white)
      ),
      onDismissed: (direction) async { 
        await _db.deleteMeal(widget.user.uid, m.id); 
      },
      child: GestureDetector(
        onTap: () => _showImagePreview(m),
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(20), 
            // FIXED: Changed withOpacity to withValues
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]
          ),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10), 
              child: _displayImage(m.imageUrl, width: 50, height: 50),
            ),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${m.calories} kcal"),
            trailing: const Icon(Icons.remove_red_eye_outlined, color: Colors.grey, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildAiList() {
    if (isLoadingWorkout) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      children: todayWorkouts.map((e) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE8F5E9), 
            child: Icon(Icons.bolt, color: Colors.green)
          ), 
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold)), 
          subtitle: Text("${e.reps} reps • ${e.duration}")
        ),
      )).toList()
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      selectedItemColor: const Color(0xFF00695C),
      unselectedItemColor: Colors.grey,
      currentIndex: 0,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: "Plan"),
        BottomNavigationBarItem(icon: Icon(Icons.insights), label: "Insights"),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Profile"),
      ],
    );
  }
}