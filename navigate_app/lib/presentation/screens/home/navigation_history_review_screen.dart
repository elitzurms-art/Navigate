import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/navigation_score.dart';
import '../../../domain/entities/user.dart';
import 'navigator_views/review_view.dart';

/// מסך תחקיר היסטורי — עוטף ReviewView עם AppBar
class NavigationHistoryReviewScreen extends StatelessWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final NavigationScore? score;

  const NavigationHistoryReviewScreen({
    super.key,
    required this.navigation,
    required this.currentUser,
    this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(navigation.name),
      ),
      body: ReviewView(
        navigation: navigation,
        currentUser: currentUser,
        initialScore: score,
      ),
    );
  }
}
