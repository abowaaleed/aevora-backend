import '../models/experience.dart';

class ExperienceManager {
  List<Experience> get experiences => Experience.allExperiences();

  List<Experience> byCategory(String category) {
    return experiences.where((experience) => experience.category == category).toList();
  }
}
