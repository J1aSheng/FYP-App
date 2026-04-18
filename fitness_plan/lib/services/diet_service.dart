import '../models/user_model.dart';

class DietService {
  double calculateBMR(UserModel user) {
    if (user.gender == "male") {
      return 10 * user.weight + 6.25 * user.height - 5 * user.age + 5;
    } else {
      return 10 * user.weight + 6.25 * user.height - 5 * user.age - 161;
    }
  }

  double calculateCalories(UserModel user) {
    double bmr = calculateBMR(user);

    switch (user.goal) {
      case "lose":
        return bmr - 500;
      case "gain":
        return bmr + 300;
      default:
        return bmr;
    }
  }
}